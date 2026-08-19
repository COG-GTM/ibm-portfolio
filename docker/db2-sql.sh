#!/usr/bin/env bash
#   Runs SQL (read from stdin, statements terminated with ";") against the DB2 container.
#
#   Usage: echo 'SELECT * FROM Portfolio;' | docker/db2-sql.sh
#
#   The DB2 CLP keeps its connection per shell process and chokes on "--" comments ahead of a
#   statement, so the SQL is prefixed with a CONNECT and stripped of comments before running.

set -euo pipefail

DB2_CONTAINER="${DB2_CONTAINER:-parity-db2}"
DB="${DB:-trader}"
SQL_FILE="$(mktemp)"
trap 'rm -f "$SQL_FILE"' EXIT

{
  echo "CONNECT TO $DB;"
  grep -v '^--' || true
} > "$SQL_FILE"

docker cp "$SQL_FILE" "$DB2_CONTAINER:/tmp/db2-sql.sql" >/dev/null
docker exec "$DB2_CONTAINER" su - db2inst1 -c "db2 ${DB2_FLAGS:--x} -tf /tmp/db2-sql.sql" |
  sed -e '/Database Connection Information/,+4d'
