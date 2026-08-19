#!/usr/bin/env bash
#   Loads createTables.ddl + seed-data.sql into both engines, so DB2 and PostgreSQL start
#   the parity run from identical state.  DB2 additionally gets the legacy stored procedures.
#
#   Usage: docker/load-schemas.sh [--recreate]

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(dirname "$HERE")"
DB2_CONTAINER="${DB2_CONTAINER:-parity-db2}"
PG_CONTAINER="${PG_CONTAINER:-parity-postgres}"
DB="${DB:-trader}"

echo "==> waiting for PostgreSQL"
until docker exec "$PG_CONTAINER" pg_isready -U postgres -d "$DB" >/dev/null 2>&1; do sleep 2; done

echo "==> waiting for DB2 (first start takes several minutes)"
until docker exec "$DB2_CONTAINER" su - db2inst1 -c "db2 connect to $DB" >/dev/null 2>&1; do sleep 10; done

echo "==> PostgreSQL: schema + seed"
docker exec -i "$PG_CONTAINER" psql -U postgres -d "$DB" -v ON_ERROR_STOP=1 <<'SQL'
DROP TABLE IF EXISTS Stock;
DROP TABLE IF EXISTS Portfolio;
SQL
docker exec -i "$PG_CONTAINER" psql -U postgres -d "$DB" -v ON_ERROR_STOP=1 < "$REPO/createTables.ddl"
docker exec -i "$PG_CONTAINER" psql -U postgres -d "$DB" -v ON_ERROR_STOP=1 < "$REPO/docker/seed-data.sql"

echo "==> DB2: schema + legacy stored procedures + seed"
docker cp "$REPO/createTables.ddl"        "$DB2_CONTAINER:/tmp/createTables.ddl"
docker cp "$REPO/stored-procs.ddl"        "$DB2_CONTAINER:/tmp/stored-procs.ddl"
docker cp "$REPO/docker/seed-data.sql"    "$DB2_CONTAINER:/tmp/seed-data.sql"
#   Two DB2 CLP quirks are worked around here:
#     * a "--" comment line ahead of a statement makes the CLP reject the file (DB21034E),
#       so comments are stripped from the files it reads;
#     * the CLP keeps its connection per shell process, so every db2 invocation has to run
#       in the same shell - no subshells - hence the plain script below.
cat > /tmp/db2-load.sh <<SCRIPT
set -e
for f in createTables.ddl stored-procs.ddl seed-data.sql; do
  grep -v '^--' /tmp/\$f > /tmp/db2-\$f
done
db2 connect to $DB
db2 "DROP TABLE Stock"     || true
db2 "DROP TABLE Portfolio" || true
db2 -tf /tmp/db2-createTables.ddl
db2 -td@ -f /tmp/db2-stored-procs.ddl
db2 -tf /tmp/db2-seed-data.sql
SCRIPT
docker cp /tmp/db2-load.sh "$DB2_CONTAINER:/tmp/db2-load.sh"
docker exec "$DB2_CONTAINER" su - db2inst1 -c "bash /tmp/db2-load.sh"

echo "==> loaded.  DB2 rows:"
printf 'CONNECT TO %s;\nSELECT COUNT(*) FROM Portfolio;\n' "$DB" > /tmp/db2-count.sql
docker cp /tmp/db2-count.sql "$DB2_CONTAINER:/tmp/db2-count.sql" >/dev/null
docker exec "$DB2_CONTAINER" su - db2inst1 -c "db2 -x -tf /tmp/db2-count.sql | grep -E '^ *[0-9]+$'"
echo "==> PostgreSQL rows:"
docker exec "$PG_CONTAINER" psql -U postgres -d "$DB" -tAc 'SELECT COUNT(*) FROM Portfolio'
