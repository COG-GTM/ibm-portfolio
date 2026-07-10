#!/usr/bin/env bash
# End-to-end REST smoke test for the portfolio microservice.
# Exercises the full CRUD golden path and prints the rows landing in Postgres.
set -euo pipefail

BASE="${BASE:-http://localhost:9080/portfolio}"
AUTH="${AUTH:-stock:trader}"
OWNER="${OWNER:-John}"
CURL=(curl -sk -u "$AUTH" -H "Accept: application/json")

echo "== 1. POST /$OWNER  (create portfolio) =="
"${CURL[@]}" -X POST "$BASE/$OWNER" ; echo

echo "== 2. PUT /$OWNER?symbol=IBM&shares=123  (add stock) =="
"${CURL[@]}" -X PUT "$BASE/$OWNER?symbol=IBM&shares=123&commission=9.99" ; echo

echo "== 3. GET /$OWNER  (read back) =="
"${CURL[@]}" "$BASE/$OWNER" ; echo

echo "== 4. GET /  (list all portfolios) =="
"${CURL[@]}" "$BASE/" ; echo

echo "== 5. Rows in Postgres =="
docker exec portfolio-postgres psql -U "${JDBC_ID:-stock}" -d "${JDBC_DB:-trader}" \
  -c 'SELECT * FROM portfolio;' -c 'SELECT owner, symbol, shares, commission FROM stock;'

echo "== 6. DELETE /$OWNER  (cleanup) =="
"${CURL[@]}" -X DELETE "$BASE/$OWNER" ; echo
echo "Smoke test complete."
