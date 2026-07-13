# DB2 → PostgreSQL Migration Plan — `portfolio` microservice

**Phase 2 blueprint.** Strategy: keep one codebase that runs against **either** backend via the
existing `JDBC_KIND=db2|postgres` switch; move the stored-procedure business logic into plain,
unit-testable Java so the PostgreSQL schema needs **no stored procedures at all**. DB2 stays
fully runnable (old proc path) for side-by-side verification and rollback.

---

## 1. Type Mappings (DB2 → PostgreSQL)

| DB2 type            | PostgreSQL type    | Used by                          | Notes |
|---------------------|--------------------|----------------------------------|-------|
| `VARCHAR(n)`        | `VARCHAR(n)`       | owner, symbol, accountID, loyalty, dateQuoted | identical semantics |
| `DOUBLE` / `DOUBLE PRECISION` | `DOUBLE PRECISION` | total, balance, commissions, price | both IEEE-754 binary64 → bit-identical arithmetic |
| `INTEGER`           | `INTEGER`          | shares                           | identical |
| PK / FK / `ON DELETE CASCADE` | same syntax | both tables                      | portable |
| SQL PL procedure (`LANGUAGE SQL`, `@` terminator) | **removed** — logic lifted to Java | UPDATE_LOYALTY_LEVEL, CALCULATE_COMMISSION | see §3 |

No identity/sequence columns exist (natural keys), so no `GENERATED ... AS IDENTITY`
conversion is required.

## 2. File-by-File Plan

| File | Action |
|------|--------|
| `createTables.ddl` | Already ANSI-portable; runs unchanged under `psql`. Canonical Postgres copy added at `migration/postgres/createTables-postgres.sql` (with explicit `DOUBLE PRECISION`, comments for psql usage). |
| `stored-procs.ddl` | **Not ported to Postgres.** Remains for the DB2 legacy path only. Logic lifted into `TradePolicy.java`. |
| `src/.../portfolio/TradePolicy.java` | **New.** Pure, static, unit-testable functions: `loyaltyFor(total)`, `baseCommission(loyalty)`, `commissionFor(loyalty, tradeValue)` — the exact tier table and half-basis-point surcharge from the procs. |
| `src/.../portfolio/PortfolioService.java` | `invokeUpdateLoyaltyLevel` / `invokeCalculateCommission` now branch on `JDBC_KIND`: `db2` → legacy `CallableStatement` proc path (unchanged); anything else (`postgres`) → `TradePolicy` + plain `PreparedStatement` UPDATEs that reproduce the procs' side effects (including `COALESCE` null handling and the read-loyalty-before-update ordering). |
| `src/test/.../TradePolicyTest.java` | **New.** JUnit tests pinning every tier boundary and the surcharge math to the proc's behavior. |
| `src/main/liberty/config/includes/postgres.xml` | Parameterize SSL: `sslMode="${JDBC_SSLMODE}"` (default `prefer`) so a plain local `postgres:16` works while managed/verify-ca deployments just set the env var. |
| `src/main/liberty/config/server.xml` | No change needed — `JDBC_KIND` include mechanism already exists (default `db2`). |
| `pom.xml` | No change — PostgreSQL driver 42.7.7 already shipped to `/config/prereqs`. |
| `Dockerfile` | No change — copies all prereq jars. |
| `migration/` | **New.** Docker Compose stack (DB2 community edition + `postgres:16` + a stock-quote stub + two portfolio instances), seed data, and the parity dashboard (Phases 3–4). |

## 3. Lifting the Stored Procedures

```text
// UPDATE_LOYALTY_LEVEL(owner, total) → loyalty          // CALCULATE_COMMISSION(owner, tradeValue) → commission
loyalty = TradePolicy.loyaltyFor(total)                  loyalty    = SELECT COALESCE(loyalty,'Basic') FROM Portfolio WHERE owner=?
UPDATE Portfolio SET loyalty=? WHERE owner=?             commission = TradePolicy.commissionFor(loyalty, tradeValue)
return loyalty                                           UPDATE Portfolio SET commissions=COALESCE(commissions,0)+?,
                                                                              balance=COALESCE(balance,0)-? WHERE owner=?
                                                         return commission
```

Both run on the same JTA-managed `DataSource` connection as before, inside the surrounding
`@Transactional` boundary, so transactional semantics are unchanged.

## 4. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Behavioral drift between proc and Java logic | `TradePolicyTest` pins boundaries (9,999.99 / 10,000 / 50,000 / 100,000 / 1,000,000; 250,000 vs 250,000.01); Phase 3/4 runs the same scenario against both backends and diff's every response + final rows. |
| Loyalty read ordering in commission calc | Java path performs the identical `SELECT COALESCE(loyalty,'Basic')` **before** applying updates, exactly like the proc. |
| NULL `balance`/`commissions` | Same `COALESCE(...,0)` applied in the UPDATE statements. |
| Postgres SSL config breaking local runs | `JDBC_SSLMODE` variable (default `prefer`). |
| Float formatting differences in JSON | Both paths serialize from the same Java `double`s via JSON-B — no DB-side formatting is involved. |
| Rollback | `JDBC_KIND=db2` restores the original proc-driven behavior with zero code changes. |

## 5. Verification Plan (Phases 3–5)

1. `docker compose` up: `ibmcom/db2` + `postgres:16`, schema + identical seed data in each.
2. Portfolio instance A → DB2 (`JDBC_KIND=db2`, **old proc path**); instance B → Postgres
   (`JDBC_KIND=postgres`, **new lifted-logic path**); both use a deterministic stock-quote stub.
3. Parity dashboard drives the same scenario against both: create → buys across loyalty tiers
   (exercising tiering + commission + block-trade surcharge) → fetch portfolio/returns → sell →
   delete; every step diffed with MATCH/MISMATCH badges plus a row-level reconciliation of both
   databases and a tamper-based negative control.
