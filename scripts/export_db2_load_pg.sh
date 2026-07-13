#!/usr/bin/env bash
# Bulk data movement: DB2 EXPORT (DEL/CSV format) -> PostgreSQL COPY.
# Assumes a DB2 container named "db2" (db2inst1/PORTFOLIO) and a Postgres
# container named "pgdb" (postgres/portfolio) on the same Docker host.
set -euo pipefail

DB2_CONTAINER="${DB2_CONTAINER:-db2}"
DB2_DB="${DB2_DB:-PORTDB}"   # DB2 database names are limited to 8 characters
PG_CONTAINER="${PG_CONTAINER:-pgdb}"

echo "== Exporting from DB2 =="
docker exec "$DB2_CONTAINER" bash -c "su - db2inst1 -c \"
  db2 connect to $DB2_DB >/dev/null &&
  db2 \\\"EXPORT TO /tmp/portfolio.del OF DEL MODIFIED BY NOCHARDEL COLDEL, SELECT owner, total, accountID FROM Portfolio\\\" &&
  db2 \\\"EXPORT TO /tmp/stock.del OF DEL MODIFIED BY NOCHARDEL COLDEL, SELECT owner, symbol, shares, price, total, dateQuoted, commission FROM Stock\\\"
\""

docker cp "$DB2_CONTAINER":/tmp/portfolio.del /tmp/portfolio.del
docker cp "$DB2_CONTAINER":/tmp/stock.del /tmp/stock.del

echo "== Loading into PostgreSQL =="
docker cp /tmp/portfolio.del "$PG_CONTAINER":/tmp/portfolio.del
docker cp /tmp/stock.del "$PG_CONTAINER":/tmp/stock.del
docker exec "$PG_CONTAINER" psql -U postgres -d portfolio -c \
  "TRUNCATE stock, portfolio;
   COPY portfolio(owner, total, accountid) FROM '/tmp/portfolio.del' WITH (FORMAT csv);
   COPY stock(owner, symbol, shares, price, total, datequoted, commission) FROM '/tmp/stock.del' WITH (FORMAT csv);"

echo "== Row counts =="
echo "-- DB2:"
docker exec "$DB2_CONTAINER" bash -c "su - db2inst1 -c \"db2 connect to $DB2_DB >/dev/null && db2 -x 'SELECT COUNT(*) FROM Portfolio' && db2 -x 'SELECT COUNT(*) FROM Stock'\""
echo "-- PostgreSQL:"
docker exec "$PG_CONTAINER" psql -U postgres -d portfolio -t -c "SELECT COUNT(*) FROM portfolio; SELECT COUNT(*) FROM stock;"
