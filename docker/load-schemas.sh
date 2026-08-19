#!/usr/bin/env bash
#   Loads the legacy DB2 schema (tables + stored procedures) and the migrated PostgreSQL
#   schema (tables only) into the containers from docker/docker-compose.yml, then loads the
#   same seed data into both.  Idempotent: re-run it to reset both engines to a clean baseline.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB2_CONTAINER="${DB2_CONTAINER:-portfolio-db2}"
PG_CONTAINER="${PG_CONTAINER:-portfolio-postgres}"
DB2_DB="${DB2_DB:-trader}"
PG_DB="${PG_DB:-trader}"
PG_USER="${PG_USER:-trader}"

#   Each "db2" CLP invocation is its own process, so the CONNECT has to travel with the
#   statements in a single script rather than being issued as a separate command.
db2_script() { # $1 = host file of SQL, $2 = statement terminator (default ";")
  local file="$1" term="${2:-;}" staged=/tmp/db2-staged.sql
  { printf 'CONNECT TO %s%s\n' "$DB2_DB" "$term"; cat "$file"; } > "$staged"
  docker cp "$staged" "$DB2_CONTAINER:$staged" > /dev/null
  local flags="-tf"
  [ "$term" = ";" ] || flags="-td$term -f"

  #   The CLP exits 1 for warnings (e.g. SQL0100W from a DELETE that matched nothing) and
  #   >=2 for real errors, so only the latter should fail the load.
  local rc=0
  docker exec "$DB2_CONTAINER" su - db2inst1 -c "db2 $flags $staged" || rc=$?
  [ "$rc" -le 1 ] || return "$rc"
}

db2_sql() { # $1 = one or more ";"-terminated statements
  local inline=/tmp/db2-inline.sql
  printf '%s\n' "$1" > "$inline"
  db2_script "$inline"
}

echo "==> waiting for DB2 to accept connections"
for _ in $(seq 1 60); do
  if db2_sql "VALUES 1;" > /dev/null 2>&1; then break; fi
  sleep 10
done
db2_sql "VALUES 1;" > /dev/null

echo "==> loading DB2 schema (legacy: tables + stored procedures)"
db2_sql "DROP TABLE Stock;"     > /dev/null 2>&1 || true
db2_sql "DROP TABLE Portfolio;" > /dev/null 2>&1 || true
db2_script "$REPO_ROOT/createTables-db2.ddl"
db2_script "$REPO_ROOT/stored-procs.ddl" '@'
echo "==> loading DB2 seed data"
db2_script "$REPO_ROOT/docker/seed.sql"

echo "==> loading PostgreSQL schema (migrated: tables only, no procedures)"
docker exec -i "$PG_CONTAINER" psql -v ON_ERROR_STOP=1 -U "$PG_USER" -d "$PG_DB" < "$REPO_ROOT/createTables.ddl"
echo "==> loading PostgreSQL seed data"
docker exec -i "$PG_CONTAINER" psql -v ON_ERROR_STOP=1 -U "$PG_USER" -d "$PG_DB" < "$REPO_ROOT/docker/seed.sql"

echo "==> DB2 row counts and procedures"
db2_sql "SELECT COUNT(*) AS PORTFOLIOS FROM Portfolio;
SELECT COUNT(*) AS STOCKS FROM Stock;
SELECT procname FROM syscat.procedures WHERE procschema = 'DB2INST1';"
echo "==> PostgreSQL row counts and procedures"
docker exec "$PG_CONTAINER" psql -U "$PG_USER" -d "$PG_DB" \
  -c 'SELECT COUNT(*) AS portfolios FROM Portfolio' \
  -c 'SELECT COUNT(*) AS stocks FROM Stock' \
  -c "SELECT COALESCE(string_agg(proname, ', '), '(none - logic lives in Java)') AS procedures FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public'"

echo "==> both schemas loaded"
