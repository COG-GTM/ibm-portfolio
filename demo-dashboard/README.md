# Migration Parity Dashboard

Live, side-by-side proof that the **same portfolio application** behaves identically
when backed by **IBM DB2** and by **PostgreSQL** — the app-level companion to the
data-level parity harness in `local/verify_migration.py`.

Two instances of the exact same WAR / Docker image run simultaneously; the **only**
difference is datasource configuration (`JDBC_KIND` + JDBC env vars). The dashboard
drives both instances through the same OLTP customer journey and diffs every REST
response field by field:

1. `POST /portfolio/{owner}` — create portfolio
2. `PUT  /portfolio/{owner}?symbol=IBM&shares=100` — buy stock
3. `PUT  /portfolio/{owner}?symbol=AAPL&shares=25` — buy another stock
4. `GET  /portfolio/{owner}` — read portfolio
5. `GET  /portfolio/` — returns / totals / loyalty across portfolios
6. `DELETE /portfolio/{owner}` — cascade delete

Each step renders the two JSON responses side by side (DB2 blue pane vs Postgres
slate pane) with differing fields highlighted, a **MATCH ✓ / MISMATCH ✗** badge,
per-side latency, and a step-by-step parity timeline. "Peek at database rows"
shows the raw rows straight out of each engine (`db2` CLI and `psql`).

Stock prices normally come from the external stock-quote microservice, which can be
unavailable or non-deterministic. `quote-stub.js` pins quotes (fixed prices + date)
and serves both instances identically, so any response difference can only come from
the database swap.

## Running the demo

```bash
# 1. Databases (DB2 takes several minutes on first start; watch: docker logs -f stocktrader-db2)
docker compose -f local/docker-compose.yml up -d

# 2. Build the app image (once)
mvn package -DskipTests
docker build -t portfolio-demo .

# 3. Pinned quote stub, on the same docker network as the databases
docker run -d --name quote-stub --network local_default \
  -v "$PWD/demo-dashboard/quote-stub.js":/quote-stub.js:ro \
  node:20-alpine node /quote-stub.js

# 4. Two identical app instances — only the datasource env differs
docker run -d --name portfolio-db2 --network local_default -p 9081:9080 \
  -e AUTH_TYPE=none -e KAFKA_ADDRESS=kafka:9092 \
  -e STOCK_QUOTE_URL=http://quote-stub:9999 \
  -e JDBC_KIND=db2 -e JDBC_HOST=db2 -e JDBC_PORT=50000 \
  -e JDBC_DB=trader -e JDBC_ID=db2inst1 -e JDBC_PASSWORD=StockTrader123 \
  portfolio-demo

docker run -d --name portfolio-pg --network local_default -p 9082:9080 \
  -e AUTH_TYPE=none -e KAFKA_ADDRESS=kafka:9092 \
  -e STOCK_QUOTE_URL=http://quote-stub:9999 \
  -e JDBC_KIND=postgres -e JDBC_HOST=postgres -e JDBC_PORT=5432 \
  -e JDBC_DB=trader -e JDBC_ID=db2inst1 -e JDBC_PASSWORD=StockTrader123 \
  portfolio-demo

# 5. Dashboard (zero npm dependencies)
node demo-dashboard/server.js     # → http://localhost:8090
```

Open http://localhost:8090 and click **Run full scenario**. All-green timeline =
the migration preserves application behavior. Check **keep data** to skip the
delete step so the identical rows can be inspected in both databases.

Configuration (env vars for `server.js`): `DB2_APP_URL` (default
`http://localhost:9081`), `PG_APP_URL` (default `http://localhost:9082`),
`APP_USER`/`APP_PASSWORD` (default `stock`/`trader`), `PORT` (default `8090`).
