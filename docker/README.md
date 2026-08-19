# Local DB2 vs PostgreSQL verification environment

Two databases, one codebase: DB2 keeps the legacy stored procedures, PostgreSQL runs the
loyalty/commission rules that were lifted into the Java service layer.

```bash
docker compose -f docker/docker-compose.yml up -d   # ibmcom/db2:11.5.8.0 + postgres:16
./docker/load-schemas.sh                            # schemas + procedures (DB2 only) + identical seed data
./tools/parity/run.sh                               # parity dashboard on http://localhost:8099/
```

| Piece | DB2 | PostgreSQL |
| --- | --- | --- |
| Container | `portfolio-db2` (port 50000) | `portfolio-postgres` (port 5432) |
| Credentials | `db2inst1` / `db2inst1`, database `trader` | `trader` / `trader`, database `trader` |
| Schema | [`createTables-db2.ddl`](../createTables-db2.ddl) | [`createTables.ddl`](../createTables.ddl) |
| Stored procedures | [`stored-procs.ddl`](../stored-procs.ddl) | none — logic lives in `portfolio.rules` |
| Seed data | [`seed.sql`](seed.sql) | [`seed.sql`](seed.sql) (same file) |

DB2 takes a few minutes to initialize on first start; `load-schemas.sh` waits for it.

Raw row inspection. Each `db2` invocation under `su -c` gets its own backend, so the connect and the
query have to travel through one client process, otherwise DB2 answers `SQL1024N`:

```bash
docker exec portfolio-db2 su - db2inst1 -c "printf 'connect to trader;\nSELECT * FROM Portfolio;\n' | db2 -t"
docker exec portfolio-postgres psql -U trader -d trader -c 'SELECT * FROM Portfolio'
```

The procedures should exist only on DB2 (note `syscat.routines`, not `syscat.procedures`, on 11.5.8):

```bash
docker exec portfolio-db2 su - db2inst1 -c "printf \"connect to trader;\nSELECT routinename, routinetype FROM syscat.routines WHERE routineschema='DB2INST1';\n\" | db2 -t"
docker exec portfolio-postgres psql -U trader -d trader -c '\df'
```
