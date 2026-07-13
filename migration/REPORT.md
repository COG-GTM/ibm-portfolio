# Migration Report — DB2 → PostgreSQL (executed live run, 2026-07-12)

Actual output from executing the phased migration in `DEMO.md`, with the trading
traffic generator running against the source database throughout.

## Timeline

| Time (UTC) | Event |
|------------|-------|
| 14:04:04 | Traffic generator started against DB2-backed app (POST/PUT/GET every 2s) |
| 14:04:42 | **Bulk load**: CDC anchor recorded at `change_id=83`, snapshot taken (14 portfolios, 24 stocks), loaded into Postgres |
| 14:04:52 | **CDC replayer** started from anchor 83; caught up within seconds, streamed continuously |
| 14:10:07 | **Reconciliation ALL GREEN while traffic flowing** (56 portfolios / 110 stocks, checksums equal, lag 0) — GO for cutover |
| 14:10:33 | Traffic stopped — cutover window opens |
| 14:10:39 | Go/no-go gate reconciliation: ALL GREEN (57 portfolios / 112 stocks, journal drained at `change_id=580`) |
| 14:10:41 | App container flipped: `JDBC_KIND=db2` → `JDBC_KIND=postgres` (same image, env-only change) |
| 14:11:01 | App healthy on Postgres — cutover window closes (**~28 s downtime**) |
| 14:11:01 | Traffic restarted against Postgres-backed app — all HTTP 200, identical API behavior |
| 14:13:01 | **Final zero-loss verification: PASS** |

## Migration statistics

- Snapshot point (CDC anchor): `change_id = 83`
- Changes replayed by CDC after the snapshot: **497** (journal drained through `change_id = 580`)
- Rows verified at cutover: 57 portfolios, 112 stocks — counts and content checksums equal on both sides
- Traffic: 207 successful requests against DB2 before cutover, 98+ against Postgres after; **0 failed requests** in either phase
- App errors on Postgres: **none** (only OpenTelemetry span-export warnings from the absent Jaeger collector)

## Go/no-go gate (with traffic running)

```
=== RECONCILIATION REPORT @ 14:10:07 UTC ===
| Table      | DB2 rows |  PG rows | DB2 checksum | PG checksum  | Status      |
|------------|----------|----------|--------------|--------------|-------------|
| Portfolio  |       56 |       56 | 4feee5847e3d | 4feee5847e3d | ✅ MATCH     |
| Stock      |      110 |      110 | eb134bd0d8f4 | eb134bd0d8f4 | ✅ MATCH     |
| CDC lag    | head=572 | appl=572 | pending=0    | replayed=489 | ✅ IN SYNC  |
OVERALL: ✅ ALL GREEN - GO for cutover
```

## Final zero-loss verification (after cutover, traffic on Postgres)

```
=== FINAL ZERO-LOSS VERIFICATION (post-cutover) @ 14:13:01 UTC ===
| Table      | DB2 rows | found in PG | missing | Status      |
|------------|----------|-------------|---------|-------------|
| Portfolio  |       57 |          57 |       0 | ✅ ALL FOUND |
| Stock      |      112 |         112 |       0 | ✅ ALL FOUND |
| CDC drain  | head=580 |    appl=580 |       0 | ✅ DRAINED   |
OVERALL: ✅ ZERO LOST TRANSACTIONS — every DB2 transaction is in PostgreSQL
```

## Phase coverage

| Phase | Covered by |
|-------|-----------|
| Discover | Schema/DDL review (`createTables.ddl`), app JDBC config discovery (Liberty includes) |
| Convert | `migration/postgres/createTables.postgres.ddl` (DB2 → Postgres DDL) |
| Move Data | `bulk_load.py` (snapshot) + `db2_cdc_setup.sql` / `cdc_replayer.py` (CDC) |
| Validate | `reconcile.py` (counts, checksums, lag; `--final` zero-loss proof) |
| Cut Over | Env-var flip of the Liberty datasource include, traffic resumed on Postgres |
| Stabilize | Post-cutover traffic + error-free app logs + final verification |
