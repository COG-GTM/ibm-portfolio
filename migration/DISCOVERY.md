# Discovery: DB2 Dependency Inventory — Portfolio microservice

Inventory of every database touchpoint in the app, produced as phase 1 of the DB2 → PostgreSQL migration.

## Data access architecture

The service uses **JPA (EclipseLink) over JTA**, not hand-written JDBC. All SQL is generated from
entity mappings and JPQL named queries, which makes the SQL surface small and highly portable.

## SQL / table access inventory

| # | Source | Statement / access | Tables | Dialect risk |
|---|--------|--------------------|--------|--------------|
| 1 | `createTables.ddl` | `CREATE TABLE Portfolio(owner VARCHAR(32) PK, total DOUBLE PRECISION, accountID VARCHAR(64))` | Portfolio | None — ANSI types |
| 2 | `createTables.ddl` | `CREATE TABLE Stock(owner, symbol, shares, price, total, dateQuoted, commission; PK(owner,symbol); FK owner → Portfolio ON DELETE CASCADE)` | Stock | None — ANSI types |
| 3 | `Portfolio.findAll` (JPQL) | `SELECT p FROM Portfolio p ORDER BY p.owner ASC` (+ pagination via `setFirstResult`/`setMaxResults` → `OFFSET/FETCH`) | Portfolio | Low — EclipseLink emits per-platform paging SQL |
| 4 | `Stock.findByOwner` (JPQL) | `SELECT s FROM Stock s WHERE s.portfolio.owner = :owner` | Stock | None |
| 5 | `Stock.findByOwnerAndSymbol` (JPQL) | `... AND s.symbol = :symbol` | Stock | None |
| 6 | `PortfolioDao` | `em.persist/find/merge/remove` → generated `INSERT/SELECT/UPDATE/DELETE` on Portfolio | Portfolio | None |
| 7 | `StockDao` | `em.persist/merge/remove` → generated `INSERT/UPDATE/DELETE` on Stock | Stock | None |
| 8 | `PortfolioService.staticInitialize` | JNDI lookup of `jdbc/Portfolio/PortfolioDB` DataSource (readiness probe) | — | None |

## DB2-specific dependencies

| Where | DB2-ism | Migration action |
|-------|---------|------------------|
| `src/main/liberty/config/includes/db2.xml` | `properties.db2.jcc` datasource (serverName/portNumber/databaseName from `JDBC_HOST/PORT/DB`), `securityMechanism="3"` | Replaced by `postgres.xml` include (`JDBC_KIND=postgres`) |
| `pom.xml` / Dockerfile `/config/prereqs` | `com.ibm.db2:jcc:12.1.0.0` driver jar | PostgreSQL driver `org.postgresql:postgresql:42.7.7` already shipped in prereqs |
| `server.xml` | `<variable name="JDBC_KIND" defaultValue="db2"/>` | Override env `JDBC_KIND=postgres` (no code change) |
| `persistence.xml` | `eclipselink.pessimistic-lock=Lock` | Portable — EclipseLink emits `FOR UPDATE` on PG |
| DB2 database naming | Database names limited to **8 chars** (`PORTFOLIO` is invalid on DB2; PG has no such limit) | Source DB named `PORTDB`; PG DB named `portfolio` |
| `includes/postgres.xml` (pre-existing) | `sslMode="verify-ca"` hardcoded → forces TLS even with `JDBC_SSL=false` | **Fixed**: `sslMode` now driven by `JDBC_SSL_MODE` variable (default `prefer`) |
| Case folding | DB2 folds unquoted identifiers to UPPERCASE, PG to lowercase | No action — all identifiers unquoted on both sides |

## Verdict

No hand-written DB2 SQL exists; the entire migration is **schema + config + data**, making this a clean
convert-and-rewire (big-bang) candidate.
