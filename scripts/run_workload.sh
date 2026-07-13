#!/usr/bin/env bash
# Scripted API workload for the Portfolio service.  Run it against the DB2-backed
# app to capture a baseline, then against the Postgres-backed app, and diff the outputs.
#
# Usage: ./run_workload.sh <base_url> <output_dir>
#   e.g. ./run_workload.sh http://localhost:9080/portfolio baseline-db2
set -euo pipefail

BASE_URL="${1:?usage: run_workload.sh <base_url> <output_dir>}"
OUT="${2:?usage: run_workload.sh <base_url> <output_dir>}"
AUTH="${WORKLOAD_AUTH:-stock:trader}"
mkdir -p "$OUT"

req() { # method path outfile
  local method="$1" path="$2" outfile="$3"
  curl -s -u "$AUTH" -X "$method" "$BASE_URL$path" \
    | python3 -m json.tool --sort-keys > "$OUT/$outfile" 2>/dev/null \
    || curl -s -u "$AUTH" -X "$method" "$BASE_URL$path" > "$OUT/$outfile"
  echo "[$method $path] -> $OUT/$outfile"
}

# 1. List pre-existing (migrated) portfolios
req GET  "/?pageSize=20"                              01_list_portfolios.json

# 2. Read each migrated portfolio (immutable=true avoids quote refresh writes)
for owner in Alice Bob Carol David Emma Frank Grace Henry; do
  req GET "/$owner" "02_get_${owner}.json"
done

# 3. Create a new portfolio and trade against it
req POST "/Demo?accountID=ACCT-9999"                  03_create_Demo.json
req PUT  "/Demo?symbol=IBM&shares=50&commission=9.99" 04_buy_IBM.json
req PUT  "/Demo?symbol=AAPL&shares=25&commission=9.99" 05_buy_AAPL.json
req GET  "/Demo"                       06_get_Demo.json

# 4. Sell (negative shares) and read back
req PUT  "/Demo?symbol=IBM&shares=-50&commission=9.99" 07_sell_IBM.json
req GET  "/Demo"                       08_get_Demo_after_sell.json

# 5. Delete the demo portfolio and verify 404 semantics
req DELETE "/Demo"                                    09_delete_Demo.json
req GET  "/Demo"                       10_get_Demo_deleted.json

# 6. Final state of all portfolios
req GET  "/?pageSize=20"                              11_final_list.json

echo "Workload complete. Responses in $OUT/"
