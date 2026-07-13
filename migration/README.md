# DB2 → PostgreSQL Migration Verification Harness

Everything needed to prove parity between the legacy DB2 stored-procedure path and the new
PostgreSQL + lifted-Java-logic path (see `docs/db2-assessment.md` and `docs/migration-plan.md`).

## Layout

| Path | Purpose |
|------|---------|
| `postgres/createTables-postgres.sql` | Converted PostgreSQL DDL (no stored procedures needed) |
| `seed/seed.sql` | Identical seed data for both databases (one portfolio per loyalty tier) |
| `docker-compose.yml` | `ibmcom/db2` + `postgres:16` + stock-quote stub + two portfolio instances |
| `stockquote-stub/` | Deterministic stock-quote microservice stub (fixed prices/dates) |
| `load-db2.sh` | Loads schema + stored procs + seed into the DB2 container |
| `dashboard/` | Parity dashboard (Flask) with MATCH/MISMATCH badges, row reconciliation, negative control |

## Running it

```bash
# 1. Build the app image (from repo root)
mvn package
docker build -t portfolio:migration .

# 2. Start the stack (DB2 first start takes ~5 minutes)
cd migration
docker compose up -d
./load-db2.sh

# 3. Launch the dashboard
pip install flask requests
python3 dashboard/app.py     # -> http://localhost:8080
```

The dashboard's scenario: **create portfolio → buy IBM/MSFT/AAPL/NVDA crossing every loyalty
tier (Basic→Bronze→Silver→Gold→Platinum, including the >250k block-trade surcharge) → fetch
portfolio/returns → sell → delete**, run simultaneously against:

- `portfolio-db2` (`:9081`) — `JDBC_KIND=db2`, **legacy stored-procedure path**
- `portfolio-pg` (`:9082`) — `JDBC_KIND=postgres`, **new in-process TradePolicy path**

Every step is diffed (MATCH/MISMATCH badges), followed by a row-level reconciliation of both
databases (via `db2` CLI and `psql`). The **negative control** button tampers one PostgreSQL
row so you can see the reconciliation genuinely flags MISMATCH.

Raw row checks by hand:

```bash
docker exec migration-db2 su - db2inst1 -c "db2 connect to trader && db2 'SELECT * FROM Portfolio'"
docker exec migration-postgres psql -U postgres -d trader -c 'SELECT * FROM Portfolio'
```
