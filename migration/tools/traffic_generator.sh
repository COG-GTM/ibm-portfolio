#!/usr/bin/env bash
# Continuous trading traffic against the Portfolio API — keeps the source database
# visibly "live" during the migration.  Creates portfolios and buys/sells stocks
# every few seconds.  Point it at either the DB2-backed or Postgres-backed instance:
#   ./traffic_generator.sh http://localhost:9080/portfolio
set -u
BASE_URL="${1:-http://localhost:9080/portfolio}"
AUTH="stock:trader"
INTERVAL="${INTERVAL:-2}"
SYMBOLS=(IBM AAPL MSFT GOOG AMZN NVDA TSLA META ORCL CRM)
i="${START_INDEX:-0}"

log() { echo "$(date -u '+%H:%M:%S') [traffic] $*"; }

log "starting traffic against ${BASE_URL} (every ${INTERVAL}s)"
while true; do
  i=$((i + 1))
  owner="trader-$i"
  http=$(curl -s -o /tmp/tg_resp.json -w '%{http_code}' -u "$AUTH" -X POST "${BASE_URL}/${owner}?accountID=acct-$((2000 + i))")
  log "POST /${owner}  -> HTTP ${http}  (new portfolio)"
  for _ in 1 2; do
    sym=${SYMBOLS[$((RANDOM % ${#SYMBOLS[@]}))]}
    shares=$((RANDOM % 50 + 1))
    http=$(curl -s -o /tmp/tg_resp.json -w '%{http_code}' -u "$AUTH" -X PUT "${BASE_URL}/${owner}?symbol=${sym}&shares=${shares}&commission=9.99")
    log "PUT  /${owner}?symbol=${sym}&shares=${shares}  -> HTTP ${http}  (buy)"
    sleep "$INTERVAL"
  done
  # occasionally sell some shares of a previous trader's stock
  if (( i % 5 == 0 && i > 1 )); then
    prev="trader-$((i - 1))"
    sym=${SYMBOLS[$((RANDOM % ${#SYMBOLS[@]}))]}
    http=$(curl -s -o /tmp/tg_resp.json -w '%{http_code}' -u "$AUTH" -X PUT "${BASE_URL}/${prev}?symbol=${sym}&shares=-1&commission=9.99")
    log "PUT  /${prev}?symbol=${sym}&shares=-1  -> HTTP ${http}  (sell)"
  fi
  http=$(curl -s -o /tmp/tg_resp.json -w '%{http_code}' -u "$AUTH" "${BASE_URL}/${owner}")
  log "GET  /${owner}  -> HTTP ${http}  (portfolio value: $(python3 -c "import json;print(json.load(open('/tmp/tg_resp.json')).get('total'))" 2>/dev/null || echo '?'))"
  sleep "$INTERVAL"
done
