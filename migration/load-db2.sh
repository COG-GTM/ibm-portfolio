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

echo "Loading schema, stored procedures, and seed data..."
docker exec migration-db2 su - db2inst1 -c "db2 connect to trader && db2 -tf /scripts/createTables.ddl && db2 -td@ -f /scripts/stored-procs.ddl && db2 -tf /scripts/seed.sql"
echo "DB2 ready."
