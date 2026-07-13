<!--
   Copyright 2025 Kyndryl, All Rights Reserved
   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at
       http://www.apache.org/licenses/LICENSE-2.0
-->

# DB2 &rarr; PostgreSQL Migration — Portfolio Microservice

This document is the migration assessment, DB2&rarr;Postgres type mapping, and a
reproducible runbook for moving the Stock Trader **portfolio** microservice
(Java 17 / Open Liberty / JPA-EclipseLink over JDBC) from **IBM DB2** to
**PostgreSQL** — with **no business-logic rewrite** and a **rollback-safe**
dual-run driven by the existing `JDBC_KIND` toggle.

---

## 1. ASSESS — DB2-specific artifacts

The service was designed to be JDBC-provider agnostic, so the DB2 coupling is
thin and lives entirely in configuration and packaging — not in Java code.

| Layer | DB2-specific artifact | Location | Migration action |
|-------|-----------------------|----------|------------------|
| JDBC driver | `com.ibm.db2:jcc` (DB2 JCC driver) | `pom.xml` | Postgres driver `org.postgresql:postgresql` already declared alongside it — **both kept**. |
| Datasource | `properties.db2.jcc` datasource, DB2 driver library, `securityMechanism="3"` | `src/main/liberty/config/includes/db2.xml` | Parallel `includes/postgres.xml` using `properties.postgresql` + `PGConnectionPoolDataSource`. |
| Engine toggle | `<variable name="JDBC_KIND" defaultValue="db2"/>` and `<include .../includes/${JDBC_KIND}.xml"/>` | `src/main/liberty/config/server.xml` | Unchanged — flipping `JDBC_KIND=postgres` swaps the datasource include. This **is** the migration switch. |
| Connection params | `JDBC_HOST`, `JDBC_PORT`, `JDBC_DB`, `JDBC_ID`, `JDBC_PASSWORD` (env vars) | both includes | Identical variable names for both engines — only the values change per environment. |
| Driver jar packaging | `target/prereqs/*.jar` copied into the image (`/config/prereqs`) | `pom.xml` (`copy-dependencies`), `Dockerfile` | `postgresql-42.7.7.jar` is emitted into `prereqs` and referenced by `postgres.xml`. No Dockerfile change needed. |
| Schema DDL | `createTables.ddl` | repo root | Already ANSI-clean; validated verbatim on Postgres 16 (see §3). |
| SQL / JPQL | EclipseLink named queries + `em.find/persist/merge` | entities & DAOs | No dialect-specific SQL. EclipseLink auto-detects the `PostgreSQLPlatform` from the JDBC connection — **no platform override required**. |

**Data-access layer verdict:** the app is genuinely portable. The only change
required to make the *same* application run on Postgres was to stop the Postgres
datasource from forcing TLS against a plain local server (see §2).

### JDBC platform note (EclipseLink)
`persistence.xml` sets **no** `eclipselink.target-database`. EclipseLink
introspects `DatabaseMetaData` at runtime and selects `DB2Platform` or
`PostgreSQLPlatform` automatically. This is why the entities, named queries and
DAOs need zero changes — confirmed by running the identical WAR against both
configurations.

---

## 2. APP DATA-ACCESS LAYER — the changes made

Everything is toggle-driven; the DB2 path is untouched.

1. **`includes/postgres.xml`** — the datasource previously hard-coded
   `sslMode="verify-ca"`, which forces the pgjdbc driver to negotiate TLS even
   when `ssl=false`. That is correct for managed/cloud Postgres but makes it
   impossible to reach a plain, non-TLS Postgres (e.g. a local container). It is
   now parameterized:

   ```diff
   + <variable name="JDBC_SSL_MODE" defaultValue="verify-ca"/>   <!-- secure default preserved -->
   - sslMode="verify-ca"
   + sslMode="${JDBC_SSL_MODE}"
   ```

   Production/cloud deployments keep the secure `verify-ca` default. For a local
   Docker Postgres, set `JDBC_SSL=false` and `JDBC_SSL_MODE=disable`.

2. **Postgres JDBC driver** — `org.postgresql:postgresql:42.7.7` is already in
   `pom.xml` (`provided` scope) and is copied into `target/prereqs` by the
   `copy-dependencies` execution, matching the jar name referenced in
   `postgres.xml` (`/config/prereqs/postgresql-42.7.7.jar`). Verified present in
   the built image — no change needed.

3. **DB2 kept working (rollback):** `includes/db2.xml`, the DB2 driver
   dependency, and `JDBC_KIND=db2` (the server default) are all unchanged.
   Rolling back the migration is a single environment-variable flip.

No Java, entity, DAO, JPQL, `persistence.xml`, or `Dockerfile` changes were
required.

---

## 3. SCHEMA — DB2 &rarr; PostgreSQL

`createTables.ddl`:

```sql
CREATE TABLE Portfolio(owner VARCHAR(32) NOT NULL, total DOUBLE PRECISION, accountID VARCHAR(64), PRIMARY KEY(owner));
CREATE TABLE Stock(owner VARCHAR(32) NOT NULL, symbol VARCHAR(8) NOT NULL, shares INTEGER, price DOUBLE PRECISION,
    total DOUBLE PRECISION, dateQuoted VARCHAR(10), commission DOUBLE PRECISION,
    FOREIGN KEY (owner) REFERENCES Portfolio(owner) ON DELETE CASCADE, PRIMARY KEY(owner, symbol));
```

This DDL is **already clean on PostgreSQL** — it uses only ANSI types and
constructs common to DB2 and Postgres, so a single file serves both engines. It
was loaded verbatim into `postgres:16` and both tables plus the FK/PK/cascade
constraints were created without modification (the compose file mounts it into
the Postgres init directory).

### Type & identifier mapping (this schema)

| Concept | DB2 | PostgreSQL | Notes |
|---------|-----|------------|-------|
| Variable-length string | `VARCHAR(n)` | `VARCHAR(n)` | Identical. |
| 64-bit float | `DOUBLE PRECISION` | `DOUBLE PRECISION` | Identical (`double` in the JPA entities). |
| 32-bit integer | `INTEGER` | `INTEGER` | Identical. |
| Primary / foreign keys | `PRIMARY KEY`, `FOREIGN KEY ... ON DELETE CASCADE` | same | Identical syntax; cascade delete preserved. |
| Unquoted identifiers | folded to **UPPER**case | folded to **lower**case | Both the DDL and EclipseLink emit *unquoted* identifiers, so the app and schema agree on each engine (`PORTFOLIO` on DB2, `portfolio` on Postgres). No quoting needed. |

### Broader DB2 &rarr; Postgres type cheat-sheet (for other Stock Trader tables)

| DB2 | PostgreSQL |
|-----|------------|
| `SMALLINT` / `INTEGER` / `BIGINT` | `SMALLINT` / `INTEGER` / `BIGINT` |
| `DECIMAL(p,s)` / `NUMERIC(p,s)` | `NUMERIC(p,s)` |
| `REAL` / `DOUBLE` / `DOUBLE PRECISION` | `REAL` / `DOUBLE PRECISION` |
| `CHAR(n)` / `VARCHAR(n)` | `CHAR(n)` / `VARCHAR(n)` |
| `CLOB` / `BLOB` | `TEXT` / `BYTEA` |
| `TIMESTAMP` / `DATE` / `TIME` | `TIMESTAMP` / `DATE` / `TIME` |
| `GENERATED ALWAYS AS IDENTITY` | `GENERATED ALWAYS AS IDENTITY` (PG 10+) or `SERIAL` |
| `VALUES CURRENT DATE` / `SYSIBM.SYSDUMMY1` | `SELECT CURRENT_DATE` (no dual table needed) |
| `FETCH FIRST n ROWS ONLY` | `FETCH FIRST n ROWS ONLY` or `LIMIT n` |

---

## 4. RUNBOOK — reproducible verification

Prerequisites: Docker + Docker Compose, and a Java 17 JDK for the Maven build.

### Postgres (default, fully verified)

```bash
# From the repo root — builds the WAR, starts Dockerized Postgres (schema
# auto-loaded), builds+runs the app against Postgres, then runs the REST test.
JAVA_HOME=/path/to/jdk-17 ./docker/scripts/run-postgres-demo.sh
```

Or step by step:

```bash
JAVA_HOME=/path/to/jdk-17 mvn -DskipTests package        # build WAR + prereqs
cd docker
docker compose up -d --build postgres portfolio          # JDBC_KIND=postgres
curl -sk http://localhost:9080/health/ready              # -> {"status":"UP"}
./scripts/smoke-test.sh                                  # full CRUD golden path
```

The golden path exercised by `smoke-test.sh`:

```
POST   /portfolio/John                       -> create portfolio
PUT    /portfolio/John?symbol=IBM&shares=123 -> add stock
GET    /portfolio/John                        -> read back (with stock)
GET    /portfolio/                            -> list all
psql   SELECT * FROM portfolio; SELECT ... FROM stock;   -> rows landed
DELETE /portfolio/John                        -> cleanup (FK cascade removes stock)
```

Inspect the rows directly in Postgres at any time:

```bash
docker exec portfolio-postgres psql -U stock -d trader -c 'SELECT * FROM portfolio;'
docker exec portfolio-postgres psql -U stock -d trader -c 'SELECT * FROM stock;'
```

> The `price`/`total` come back as `-1` unless the sibling **stock-quote**
> microservice is running; the service gracefully falls back to cached values.
> This does not affect the persistence/migration story — the rows still land in
> Postgres.

### DB2 (rollback path — verified)

The identical app image runs against DB2 by flipping the toggle. This was
**verified end-to-end** in this environment: `icr.io/db2_community/db2:11.5.9.0`
was pulled and started, the schema loaded, and the same `portfolio:demo` image
run with `JDBC_KIND=db2` served the REST CRUD path with rows landing in DB2.

```bash
cd docker
docker compose --profile db2 up -d db2                 # privileged, LICENSE=accept; ~2-3 min first boot
docker logs -f portfolio-db2                           # wait for "Setup has completed."

# load schema into DB2
docker cp ../createTables.ddl portfolio-db2:/tmp/createTables.ddl
docker exec portfolio-db2 su - db2inst1 -c "db2 connect to trader; db2 -tf /tmp/createTables.ddl"

# run the SAME image against DB2 — only JDBC_KIND / connection vars change
docker run -d --name portfolio-app-db2 --network docker_default \
  -e JDBC_KIND=db2 -e AUTH_TYPE=none \
  -e JWT_AUDIENCE=stock-trader -e JWT_ISSUER=http://stock-trader.ibm.com \
  -e JDBC_HOST=db2 -e JDBC_PORT=50000 -e JDBC_DB=trader \
  -e JDBC_ID=db2inst1 -e JDBC_PASSWORD=trader -e JDBC_SSL=false \
  -e KAFKA_ADDRESS=localhost:9092 -p 9081:9080 portfolio:demo

curl -sk -u stock:trader -X POST 'http://localhost:9081/portfolio/Jane'
curl -sk -u stock:trader -X PUT  'http://localhost:9081/portfolio/Jane?symbol=IBM&shares=50&commission=9.99'
docker exec portfolio-db2 su - db2inst1 -c "db2 connect to trader; db2 'select owner,symbol,shares from stock'"
```

Both engines were exercised with the **same WAR/image** — the only difference is
the `JDBC_KIND` value (and the connection env vars). See `docker/README.md`.

---

## 5. SDLC themes demonstrated

- **ASSESS** — this document: inventory of DB2 artifacts + type mapping + plan.
- **DATA-ACCESS LAYER** — same app, no business-logic rewrite; migration is a
  config toggle (`JDBC_KIND`) with a secure-by-default, locally-overridable SSL
  posture.
- **SCHEMA** — DDL validated on Postgres 16; DB2&rarr;Postgres type mapping.
- **VERIFY** — Dockerized Postgres, real `mvn package`, real REST CRUD, rows
  shown in `psql`, all scripted for reproducibility.
- **ROLLBACK** — DB2 path fully intact; revert = flip one environment variable.
