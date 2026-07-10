#!/usr/bin/env bash
# One-shot reproducible Postgres demo:
#   1. build the WAR (Java 17) + prereqs (JDBC drivers)
#   2. start Dockerized Postgres (schema auto-loaded from createTables.ddl)
#   3. build + start the app image against Postgres (JDBC_KIND=postgres)
#   4. wait for readiness and run the REST smoke test
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_DIR="$REPO_ROOT/docker"
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}"

echo ">> Building WAR with $($JAVA_HOME/bin/java -version 2>&1 | head -1)"
(cd "$REPO_ROOT" && mvn -q -DskipTests package)

echo ">> Starting Postgres + portfolio app"
(cd "$COMPOSE_DIR" && docker compose up -d --build postgres portfolio)

echo ">> Waiting for the app to report ready ..."
for i in $(seq 1 60); do
  if curl -sk -o /dev/null -w '%{http_code}' http://localhost:9080/health/ready | grep -q 200; then
    echo "   app is ready"; break
  fi
  sleep 3
  [ "$i" = "60" ] && { echo "app did not become ready in time"; exit 1; }
done

echo ">> Running smoke test"
"$COMPOSE_DIR/scripts/smoke-test.sh"
