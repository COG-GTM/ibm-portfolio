# DEMO.md — DB2 → PostgreSQL "Convert-and-Rewire" Live Demo Runbook

Demo Flow A: big-bang replatform of the IBM Stock Trader **Portfolio** microservice
(Java / Open Liberty / JPA) from **DB2** to **PostgreSQL**, executed live in ~15 minutes.

Everything below was validated end-to-end; each step is copy-pasteable.

## Prerequisites (do BEFORE the demo — DB2 takes ~5-10 min to initialize)

```bash
mvn package -DskipTests                     # needs JDK 17
docker build -t portfolio:demo .
docker network create stocktrader

# Source: DB2 (must be --privileged; wait for "Setup has completed" in logs)
docker run -d --name db2 --privileged --network stocktrader \
  -e LICENSE=accept -e DB2INST1_PASSWORD=db2pass -p 50000:50000 icr.io/db2_community/db2
docker logs -f db2       # wait for "(*) Setup has completed."

# Create + seed the source database (DB2 db names are limited to 8 chars!)
docker cp createTables.ddl db2:/tmp/ && docker cp migration/seed-db2.sql db2:/tmp/seed.sql
docker exec -i db2 su - db2inst1 <<'EOF'
db2 create database PORTDB
db2 connect to PORTDB
db2 -tf /tmp/createTables.ddl
db2 -tf /tmp/seed.sql
EOF

# Target: PostgreSQL (instant)
docker run -d --name pgdb --network stocktrader \
  -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=pgpass -e POSTGRES_DB=portfolio -p 5442:5432 postgres:16
```

## Live demo script

### Act 1 — "This is a real DB2 app" (2 min)

```bash
docker run -d --name portfolio-db2 --network stocktrader -p 9080:9080 \
  -e AUTH_TYPE=none -e JDBC_KIND=db2 -e JDBC_HOST=db2 -e JDBC_PORT=50000 \
  -e JDBC_DB=PORTDB -e JDBC_ID=db2inst1 -e JDBC_PASSWORD=db2pass \
  -e KAFKA_ADDRESS=disabled:9092 portfolio:demo

curl -s -u stock:trader http://localhost:9080/portfolio/ | jq .
```

> **WOW moment #1**: a genuine DB2 LUW 12.1 container and a Liberty app talking to it —
> not a mock. Show `docker exec -i db2 su - db2inst1` + `db2 "SELECT * FROM Portfolio"` if asked.

### Act 2 — Capture the DB2 baseline (2 min)

```bash
./scripts/run_workload.sh http://localhost:9080/portfolio baseline-db2
```

18 API calls (list, per-owner reads with live stock detail, create/buy/sell/delete lifecycle)
saved as canonical JSON. *"This is our behavioral contract — Postgres must reproduce it exactly."*

### Act 3 — Convert + move the data (3 min)

```bash
# Schema conversion (show the file — types were already ANSI; discovery told us this)
docker cp createTables-postgres.ddl pgdb:/tmp/schema.sql
docker exec pgdb psql -U postgres -d portfolio -f /tmp/schema.sql

# Bulk move: DB2 EXPORT -> CSV -> Postgres COPY, with row counts printed
./scripts/export_db2_load_pg.sh
```

> **WOW moment #2**: the row counts print side by side — 8 and 15 on both engines.

### Act 4 — Rewire, zero code changes (2 min)

```bash
docker run -d --name portfolio-pg --network stocktrader -p 9081:9080 \
  -e AUTH_TYPE=none -e JDBC_KIND=postgres -e JDBC_HOST=pgdb -e JDBC_PORT=5432 \
  -e JDBC_DB=portfolio -e JDBC_ID=postgres -e JDBC_PASSWORD=pgpass \
  -e KAFKA_ADDRESS=disabled:9092 portfolio:demo

curl -s -u stock:trader http://localhost:9081/portfolio/ | jq .
```

> **WOW moment #3**: the *same container image* is now serving from PostgreSQL — the switch is
> one env var (`JDBC_KIND=postgres`). Mention the one real fix Devin made: the shipped
> `postgres.xml` hardcoded `sslMode="verify-ca"` and refused to connect to a non-TLS server.

### Act 5 — Prove identical behavior (3 min)

```bash
./scripts/run_workload.sh http://localhost:9081/portfolio postgres
diff -r baseline-db2 postgres && echo IDENTICAL
./scripts/reconcile.sh          # row counts + per-table checksums
```

> **WOW moment #4 (the closer)**: `diff` prints **nothing** — 18/18 JSON responses byte-identical —
> and the reconciliation table shows matching MD5 checksums per table. Put
> `migration/VALIDATION.md` on screen.

## Talking points

- **Discover → Convert → Move → Rewire → Validate** ran end-to-end in one Devin session.
- The app needed **zero Java changes**: JPA + config-driven datasource made this a schema/config/data problem.
- The issues that *did* surface (SSL mode, DB2 8-char DB names, build pin) are exactly the kind of
  friction Devin grinds through autonomously.
- Same harness scales: point `run_workload.sh`/`reconcile.sh` at any table set for real estates.

## Timing budget

| Segment | Time |
|---------|------|
| Pre-staged: DB2 init + image build | 10-15 min (before the call) |
| Acts 1-5 live | ~12-15 min |
