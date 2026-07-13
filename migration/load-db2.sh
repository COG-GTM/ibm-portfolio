#!/usr/bin/env bash
# Loads the DB2 schema, the legacy stored procedures, and the seed data into the
# migration-db2 container.  Run after `docker compose up -d` once DB2 finishes
# initializing (watch `docker logs -f migration-db2` for "Setup has completed").
set -euo pipefail

echo "Waiting for DB2 to finish initializing (this can take several minutes on first start)..."
until docker logs migration-db2 2>&1 | grep -q "Setup has completed"; do
  sleep 10
  echo "  ...still initializing"
done

# Each db2 CLP invocation from a non-interactive shell gets its own backend, so the
# CONNECT must live inside the same script that runs the statements.
echo "Loading schema, stored procedures, and seed data..."
docker exec migration-db2 su - db2inst1 -c "
  { echo 'CONNECT TO trader;'; cat /scripts/createTables.ddl; } > /tmp/01-tables.sql &&
  { echo 'CONNECT TO trader@'; cat /scripts/stored-procs.ddl; } > /tmp/02-procs.sql &&
  { echo 'CONNECT TO trader;'; cat /scripts/seed.sql; }        > /tmp/03-seed.sql &&
  db2 -tvf /tmp/01-tables.sql && db2 -td@ -vf /tmp/02-procs.sql && db2 -tvf /tmp/03-seed.sql"
echo "DB2 ready."
