# Docker demo — DB2 &rarr; PostgreSQL migration

Reproducible, containerized proof that the **portfolio** microservice runs
against PostgreSQL with no code changes, driven by the existing `JDBC_KIND`
toggle. See [`../MIGRATION.md`](../MIGRATION.md) for the full assessment,
type-mapping and narrative.

## Contents

| File | Purpose |
|------|---------|
| `docker-compose.yml` | `postgres` (target), `portfolio` (the app, JDBC_KIND=postgres), and a best-effort `db2` service behind the `db2` profile. |
| `scripts/run-postgres-demo.sh` | One-shot: `mvn package` &rarr; start Postgres + app &rarr; wait for ready &rarr; run smoke test. |
| `scripts/smoke-test.sh` | REST CRUD golden path + `psql` dump of the resulting rows. |

## Quick start (PostgreSQL)

```bash
# from repo root
JAVA_HOME=/path/to/jdk-17 ./docker/scripts/run-postgres-demo.sh
```

Manual:

```bash
JAVA_HOME=/path/to/jdk-17 mvn -DskipTests package
cd docker
docker compose up -d --build postgres portfolio
curl -sk http://localhost:9080/health/ready        # {"status":"UP"}
./scripts/smoke-test.sh
```

App: <http://localhost:9080/portfolio/> (basic auth `stock:trader`, because the
compose sets `AUTH_TYPE=none` which enables the sample basic registry).

Inspect Postgres directly:

```bash
docker exec portfolio-postgres psql -U stock -d trader -c 'SELECT * FROM portfolio;'
docker exec portfolio-postgres psql -U stock -d trader -c 'SELECT * FROM stock;'
```

Tear down: `docker compose down -v`.

## The migration toggle

The app image is engine-agnostic. Everything below is set in `docker-compose.yml`:

| Variable | Postgres value | Meaning |
|----------|----------------|---------|
| `JDBC_KIND` | `postgres` | Selects `includes/postgres.xml` at server start (was `db2`). |
| `JDBC_SSL` / `JDBC_SSL_MODE` | `false` / `disable` | Talk to a plain, non-TLS local Postgres. Cloud/managed Postgres keeps the secure `verify-ca` default. |
| `JDBC_HOST/PORT/DB/ID/PASSWORD` | `postgres` / `5432` / `trader` / `stock` / `trader` | Connection params (same var names for DB2). |

To **roll back to DB2**, flip `JDBC_KIND=db2` and point the `JDBC_*` vars at a
DB2 instance — no rebuild of the application code required.

## DB2 (rollback path — verified)

```bash
docker compose --profile db2 up -d db2
docker logs -f portfolio-db2      # wait for "Setup has completed." (~2-3 min first boot)
```

The `icr.io/db2_community/db2` image requires `privileged: true` and
`LICENSE=accept`. It demonstrates the rollback path: the **same** `portfolio:demo`
image runs against DB2 by setting `JDBC_KIND=db2`. This was verified end-to-end
(schema loaded, REST CRUD served, rows landed in DB2) — see the DB2 section of
[`../MIGRATION.md`](../MIGRATION.md) for the exact commands. The Postgres path is
the target of this migration; DB2 stays intact so a rollback is a one-variable flip.
