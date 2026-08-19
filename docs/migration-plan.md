# Migration plan — DB2 → PostgreSQL (portfolio microservice)

Phase 1 deliverable, executed in Phase 2. Companion to [`db2-assessment.md`](db2-assessment.md).

## Objective and shape of the change

Move the `portfolio` service from IBM DB2 to PostgreSQL **without a fork**: one codebase, one
WAR, `JDBC_KIND=db2|postgres` selecting the backend. The schema is nearly dialect-neutral, so
the substance of the migration is getting the business logic out of the database:

```
BEFORE                                   AFTER
PortfolioService                         PortfolioService
  └─ CallableStatement                     ├─ LoyaltyRules.levelFor(total)          (pure)
       CALL UPDATE_LOYALTY_LEVEL   ──►     ├─ CommissionRules.commissionFor(...)    (pure)
       CALL CALCULATE_COMMISSION           └─ postCommission() + PortfolioDao       (persistence)
  (DB2 SQL PL owns the rules)            (JDBC_KIND=db2 still calls the procedures)
```

## Type mappings

| DB2 type used here | PostgreSQL type | Note |
|---|---|---|
| `VARCHAR(n)` | `VARCHAR(n)` | identical semantics; length in characters on both |
| `DOUBLE` / `DOUBLE PRECISION` | `DOUBLE PRECISION` | DB2's `DOUBLE` is a synonym; Postgres has no `DOUBLE` |
| `INTEGER` | `INTEGER` | identical |
| `VARCHAR(10)` holding `yyyy-MM-dd` | `VARCHAR(10)` | deliberately **not** promoted to `DATE`; the JSON contract sends a string |

Types not present in this schema but worth recording for the wider Stock Trader estate:

| DB2 | PostgreSQL |
|---|---|
| `DECIMAL(p,s)` / `NUMERIC` | `NUMERIC(p,s)` |
| `TIMESTAMP` | `TIMESTAMP` (use `TIMESTAMPTZ` if an offset matters) |
| `CLOB` / `BLOB` | `TEXT` / `BYTEA` |
| `GENERATED ALWAYS AS IDENTITY` | `GENERATED ALWAYS AS IDENTITY` (or `BIGSERIAL` pre-10) |
| `VALUES (...)` singleton select | `SELECT ...` without `FROM` |
| `CURRENT DATE`, `CURRENT TIMESTAMP` | `CURRENT_DATE`, `CURRENT_TIMESTAMP` |
| `FETCH FIRST n ROWS ONLY` | `LIMIT n` (Postgres 8.4+ also accepts `FETCH FIRST`) |
| `SYSCAT.TABLES` | `information_schema.tables` / `pg_catalog` |

## File-by-file plan

| File | Action |
|---|---|
| `createTables.ddl` | **Convert to PostgreSQL.** `DOUBLE PRECISION` throughout, `DEFAULT`s for `total`/`loyalty`/`balance`/`commissions`, `IF NOT EXISTS` for idempotent reloads, a `CHECK` constraint on the five legal loyalty values, and an explicit `stock_owner_idx` on the FK column (DB2 indexes FKs implicitly, PostgreSQL does not). No stored procedures. |
| `createTables-db2.ddl` | **New.** Verbatim legacy DB2 schema, so `JDBC_KIND=db2` and the parity harness keep working. |
| `stored-procs.ddl` | Keep, DB2-only. Header notes it is legacy and that the rules now live in Java. |
| `.../portfolio/rules/LoyaltyRules.java` | **New.** `levelFor(total)` — the `UPDATE_LOYALTY_LEVEL` `CASE` ladder with the thresholds as named constants. Pure, no JDBC. |
| `.../portfolio/rules/CommissionRules.java` | **New.** `commissionFor(loyalty, tradeValue)` + `baseCommissionFor(loyalty)` — the tier schedule and the block-trade surcharge. Pure. |
| `.../portfolio/PortfolioService.java` | `useStoredProcedures = "db2".equalsIgnoreCase(JDBC_KIND)`. `invokeUpdateLoyaltyLevel` → `updateLoyaltyLevel`, returning `LoyaltyRules.levelFor(total)` unless on DB2. `invokeCalculateCommission` → `applyCommission(portfolio, ...)`, which on Postgres computes the commission from the entity's loyalty, applies `postCommission` (`commissions +=`, `balance -=`) and persists via `PortfolioDao`. The DB2 branch keeps the exact `CallableStatement` code and now also syncs the entity the procedure wrote behind JPA's back. |
| `src/test/java/.../rules/*Test.java` | **New.** JUnit coverage of every tier boundary, the inclusive thresholds, unknown/`null` loyalty, and the surcharge boundary at exactly 250,000. |
| `src/main/liberty/config/server.xml` | `JDBC_KIND` default `db2` → `postgres`. |
| `src/main/liberty/config/includes/postgres.xml` | `sslMode` hard-coded `verify-ca` → `${JDBC_SSL_MODE}` (still defaulting to `verify-ca`) so a local/containerised database can use `disable`. |
| `src/main/liberty/config/includes/db2.xml` | Unchanged — the legacy backend must stay byte-for-byte runnable. |
| `pom.xml` | Unchanged. `org.postgresql:postgresql` and `com.ibm.db2:jcc` are both already `provided`, and both jars are already copied into `target/prereqs`. |
| `docker/docker-compose.yml`, `docker/load-schemas.sh`, `docker/seed.sql` | **New.** `ibmcom/db2` + `postgres:16` with identical seed data for Phase 3/4 verification. |
| `tools/parity/` | **New.** Parity harness + dashboard that runs the same scenario against both engines. |
| `docs/` | This plan and the assessment. |
| `manifests/`, `chart/` | Deliberately untouched in this PR: they read `JDBC_HOST/PORT/DB/ID/PASSWORD` from a secret that happens to be *named* `db2`, so they work against Postgres by repointing that secret. Renaming the secret is a separate, coordinated change. |

## Behaviour that must not drift

1. Commission is computed from the loyalty level **as it stands before the trade** — the
   procedure read `Portfolio.loyalty` at call time, and `applyCommission` reads the same field
   off the entity loaded at the start of the request.
2. Loyalty is recomputed from the **refreshed** portfolio total during `GET /{owner}`, i.e. after
   stock prices are re-quoted, and the caller persists it.
3. `commissions` accumulates and `balance` is debited by exactly the returned commission, once
   per trade.
4. Unknown, mixed-case or `NULL` loyalty is charged as `Basic`.
5. `DELETE FROM Portfolio` still removes the owner's `Stock` rows by FK cascade.

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Lifted logic silently diverges from the procedures | Unit tests pin every threshold and boundary; the parity harness runs the *procedure* path against DB2 and the *Java* path against Postgres in the same scenario and diffs the responses and the final rows |
| Floating-point money compares unequal across engines | Compare with a tolerance (1e-6) and keep the arithmetic order identical to the procedures |
| Green dashboards that prove nothing | A negative control tampers a Postgres row and the dashboard must flag `MISMATCH` |
| Postgres FK delete performance regression | Explicit `stock_owner_idx` on `Stock(owner)` |
| `sslMode=verify-ca` breaks non-TLS/local databases | `JDBC_SSL_MODE` variable, default unchanged |
| Deployments relying on the old `JDBC_KIND` default | Default flips to `postgres` intentionally, and is called out in the PR; DB2 deployments set `JDBC_KIND=db2` |
| Rollback | Set `JDBC_KIND=db2` and repoint the datasource secret; the DB2 DDL and procedures are still in the repo, and no DB2 artifact was dropped |

## Verification strategy (Phases 3–5)

1. `docker compose -f docker/docker-compose.yml up -d` — `ibmcom/db2:11.5.8.0` and `postgres:16`.
2. `./docker/load-schemas.sh` — DB2 gets `createTables-db2.ddl` + `stored-procs.ddl`, Postgres gets
   `createTables.ddl`, both get the same `seed.sql` rows.
3. `mvn test` — the lifted rules against their pinned boundaries.
4. `tools/parity/run.sh` — dashboard on :8099 driving create → buy across loyalty tiers → fetch →
   sell → delete on both engines, step-by-step `MATCH`/`MISMATCH`, a row-level reconciliation
   table, and a negative control.
5. Raw rows read back through the `db2` CLI and `psql`, recorded on screen.
