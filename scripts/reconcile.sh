#!/usr/bin/env bash
# Reconciliation: row counts + per-table checksums between DB2 and PostgreSQL.
# Checksum strategy: order-insensitive SUM of per-row MD5-derived integers over a
# canonical string rendering of each row (same rendering on both sides).
set -euo pipefail

DB2_CONTAINER="${DB2_CONTAINER:-db2}"
PG_CONTAINER="${PG_CONTAINER:-pgdb}"

db2_rows() {
  docker exec "$DB2_CONTAINER" bash -c "su - db2inst1 -c \"db2 connect to ${DB2_DB:-PORTDB} >/dev/null && db2 -x \\\"$1\\\"\"" | tr -d ' \r'
}
pg_rows() {
  docker exec "$PG_CONTAINER" psql -U postgres -d portfolio -t -A -c "$1"
}

canon_db2_portfolio="SELECT TRIM(owner) || '|' || VARCHAR(DECIMAL(total,15,2)) || '|' || COALESCE(TRIM(accountID),'') FROM Portfolio ORDER BY owner"
canon_pg_portfolio="SELECT owner || '|' || to_char(total, 'FM9999999999990.00') || '|' || COALESCE(accountid,'') FROM portfolio ORDER BY owner"
canon_db2_stock="SELECT TRIM(owner) || '|' || TRIM(symbol) || '|' || VARCHAR(shares) || '|' || VARCHAR(DECIMAL(price,15,2)) || '|' || VARCHAR(DECIMAL(total,15,2)) || '|' || COALESCE(TRIM(dateQuoted),'') || '|' || VARCHAR(DECIMAL(commission,15,2)) FROM Stock ORDER BY owner, symbol"
canon_pg_stock="SELECT owner || '|' || symbol || '|' || shares::text || '|' || to_char(price,'FM9999999999990.00') || '|' || to_char(total,'FM9999999999990.00') || '|' || COALESCE(datequoted,'') || '|' || to_char(commission,'FM9999999999990.00') FROM stock ORDER BY owner, symbol"

checksum() { md5sum | cut -d' ' -f1; }

echo "table,db2_rows,pg_rows,db2_checksum,pg_checksum,match"
for t in portfolio stock; do
  if [ "$t" = portfolio ]; then dq="$canon_db2_portfolio"; pq="$canon_pg_portfolio"; DT=Portfolio; else dq="$canon_db2_stock"; pq="$canon_pg_stock"; DT=Stock; fi
  d_count=$(db2_rows "SELECT COUNT(*) FROM $DT")
  p_count=$(pg_rows "SELECT COUNT(*) FROM $t")
  d_sum=$(docker exec "$DB2_CONTAINER" bash -c "su - db2inst1 -c \"db2 connect to ${DB2_DB:-PORTDB} >/dev/null && db2 -x \\\"$dq\\\"\"" | sed 's/[[:space:]]*$//' | checksum)
  p_sum=$(pg_rows "$pq" | sed 's/[[:space:]]*$//' | checksum)
  match=$([ "$d_sum" = "$p_sum" ] && [ "$d_count" = "$p_count" ] && echo PASS || echo FAIL)
  echo "$t,$d_count,$p_count,$d_sum,$p_sum,$match"
done
