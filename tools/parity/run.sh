#!/usr/bin/env bash
# Compiles and starts the DB2 vs PostgreSQL parity dashboard on http://localhost:8099/
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$REPO_ROOT/target/parity-classes"
PORT="${PARITY_PORT:-8099}"

DB2_JAR="$(ls "$HOME"/.m2/repository/com/ibm/db2/jcc/*/jcc-*.jar | tail -1)"
PG_JAR="$(ls "$HOME"/.m2/repository/org/postgresql/postgresql/*/postgresql-*.jar | tail -1)"
CP="$DB2_JAR:$PG_JAR"

mkdir -p "$OUT"
javac -nowarn -cp "$CP" -d "$OUT" \
  "$REPO_ROOT/src/main/java/com/ibm/hybrid/cloud/sample/stocktrader/portfolio/rules/LoyaltyRules.java" \
  "$REPO_ROOT/src/main/java/com/ibm/hybrid/cloud/sample/stocktrader/portfolio/rules/CommissionRules.java" \
  "$REPO_ROOT/tools/parity/ParityHarness.java"

cd "$REPO_ROOT"
exec java -cp "$OUT:$CP" \
  -Dparity.port="$PORT" \
  -Dparity.dashboard="$REPO_ROOT/tools/parity/dashboard.html" \
  com.ibm.hybrid.cloud.sample.stocktrader.portfolio.parity.ParityHarness
