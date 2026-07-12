# Demo Flow B — DB2 → PostgreSQL OLTP Migration with Bulk Load + CDC + Live Cutover

A zero/minimal-downtime migration of the Stock Trader **Portfolio** microservice from
**DB2** to **PostgreSQL**, with live trading traffic running the whole time:

1. **Bulk load** — history is snapshotted from DB2 and loaded into Postgres.
2. **CDC** — ongoing changes are captured on DB2 (trigger journal, standing in for
   log-based CDC such as Q-Replication/Debezium) and replayed to Postgres in order.
3. **Reconcile** — row counts + content checksums + replication lag, all-green gate.
4. **Cut over** — the app is flipped to Postgres via env vars (Liberty config include),
   traffic resumes, and a final reconciliation proves zero lost transactions.

## Topology

```
 traffic_generator.sh ──▶ Portfolio app (Open Liberty, :9080) ──▶ DB2 (:50000)
                                   │                                 │ triggers
                                   ▼                                 ▼
                          mock stock-quote svc            CDC_CHANGES journal
                                                                     │ cdc_replayer.py
                                                                     ▼
                                              PostgreSQL (:5432)  ◀── bulk_load.py
```

All components run in Docker on the `migration-net` network.

## 0. Pre-stage (before the audience arrives — DB2 alone takes ~5 min to init)

```bash
mvn clean package -DskipTests               # requires JDK 17
docker build -t portfolio:demo .
docker network create migration-net

# DB2 source (takes several minutes to initialize)
docker run -d --name db2 --privileged --network migration-net \
  -e LICENSE=accept -e DB2INST1_PASSWORD=passw0rd -e DBNAME=STOCKTRD \
  -p 50000:50000 icr.io/db2_community/db2
docker logs -f db2        # wait for "Setup has completed"

# PostgreSQL target
docker run -d --name postgres --network migration-net \
  -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=passw0rd -e POSTGRES_DB=stocktrader \
  -p 5432:5432 postgres:16

# Schema + seed history + CDC journal on DB2
docker cp createTables.ddl db2:/tmp/ && docker cp migration/db2/seedData.sql db2:/tmp/
docker cp migration/cdc/db2_cdc_setup.sql db2:/tmp/
docker exec db2 su - db2inst1 -c "db2 connect to STOCKTRD && db2 -tf /tmp/createTables.ddl && db2 -tf /tmp/seedData.sql && db2 -td@ -f /tmp/db2_cdc_setup.sql"

# Converted schema on Postgres
docker exec -i postgres psql -U postgres -d stocktrader < migration/postgres/createTables.postgres.ddl

# Mock stock-quote microservice (prices trades)
docker run -d --name stock-quote-service --network migration-net \
  -v "$PWD/migration/tools:/app" python:3.12-alpine python /app/mock_stock_quote.py

# Portfolio app on DB2
docker run -d --name portfolio-db2 --network migration-net -p 9080:9080 \
  -e AUTH_TYPE=none -e JDBC_KIND=db2 -e JDBC_HOST=db2 -e JDBC_PORT=50000 \
  -e JDBC_DB=STOCKTRD -e JDBC_ID=db2inst1 -e JDBC_PASSWORD=passw0rd \
  -e KAFKA_ADDRESS=disabled portfolio:demo
curl -u stock:trader http://localhost:9080/portfolio/   # sanity check
```

## 1. LIVE: start traffic against DB2 (terminal 1)

```bash
./migration/tools/traffic_generator.sh http://localhost:9080/portfolio
```
Point out: every few seconds a new portfolio is created and stocks are bought —
the source database is live.

## 2. LIVE: bulk load while traffic flows (terminal 2)

```bash
python3 migration/tools/bulk_load.py
```
Point out: the **CDC anchor is recorded before the snapshot**, so anything that
changes mid-snapshot is also in the journal — nothing can fall in the gap.

## 3. LIVE: start the CDC replayer (terminal 3, leave running)

```bash
python3 migration/tools/cdc_replayer.py
```
Point out: it starts exactly at the snapshot anchor and streams every journaled
change to Postgres in order; lag is printed on each poll.

## 4. LIVE: reconcile until all-green (terminal 2)

```bash
python3 migration/tools/reconcile.py --watch
```
Run it while traffic still flows. Momentary `LAGGING`/`MISMATCH` lines show the
system is really live; within a poll or two it goes **ALL GREEN — GO for cutover**.

## 5. LIVE: cut over (terminal 1)

```bash
# a) stop traffic (start of the brief cutover window)
Ctrl-C the traffic generator

# b) let the replayer drain, then verify go/no-go gate
python3 migration/tools/reconcile.py        # must print ALL GREEN

# c) flip the app to Postgres (same image, env-var change only)
docker rm -f portfolio-db2
docker run -d --name portfolio-postgres --network migration-net -p 9080:9080 \
  -e AUTH_TYPE=none -e JDBC_KIND=postgres -e JDBC_HOST=postgres -e JDBC_PORT=5432 \
  -e JDBC_DB=stocktrader -e JDBC_ID=postgres -e JDBC_PASSWORD=passw0rd \
  -e KAFKA_ADDRESS=disabled portfolio:demo
until curl -sf -u stock:trader http://localhost:9080/portfolio/ > /dev/null; do sleep 2; done

# d) resume traffic — now writing to Postgres (end of cutover window)
START_INDEX=1000 ./migration/tools/traffic_generator.sh http://localhost:9080/portfolio
```

## 6. LIVE: prove zero loss

```bash
# stop the replayer (Ctrl-C in terminal 3) — DB2 is now frozen history
python3 migration/tools/reconcile.py --final   # zero-loss proof
curl -u stock:trader "http://localhost:9080/portfolio/trader-1"   # pre-migration data served from Postgres
```
Post-cutover traffic exists only in Postgres (by design), so `--final` verifies
that every row DB2 ever had is present in Postgres (source ⊆ target, quote-cache
columns excluded since the app refreshes them on every read) and that the CDC
journal is fully drained → **zero lost transactions**.

## Talking points

- The CDC journal is trigger-based for demo simplicity; in production this slot is
  filled by log-based CDC (IBM Q-Replication, InfoSphere CDC, or Debezium's Db2
  connector) — the anchor/replay/reconcile choreography is identical.
- The app itself needed **no code changes** — plain JDBC/JPA + a Liberty config
  include flip (`JDBC_KIND=db2` → `JDBC_KIND=postgres`).
- Replays are idempotent (upsert/delete), so the replayer can crash and restart
  safely, and overlap between snapshot and journal is harmless.
