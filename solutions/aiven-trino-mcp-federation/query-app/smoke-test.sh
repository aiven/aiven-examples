#!/usr/bin/env bash
#
# smoke-test.sh — validate that query-app's Trino can reach Snowflake Open Catalog
# and read the Iceberg data (the keystone integration: Trino -> Open Catalog ->
# cross-region S3). Run it against a running query-app (see README).
#
# Usage:
#   ./smoke-test.sh                     # catalogs + schemas in `iceberg`
#   ./smoke-test.sh <namespace>         # + tables in that namespace
#   ./smoke-test.sh <namespace> <table> # + SELECT count(*) on that table (default table: order)
#
# Env:
#   TRINO_CONTAINER  docker container name (default: trino)
set -euo pipefail

CONTAINER="${TRINO_CONTAINER:-trino}"

run() {
  echo "  trino> $1"
  docker exec -i "$CONTAINER" trino --execute "$1"
}

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "ERROR: Trino container '$CONTAINER' is not running. Start query-app first:" >&2
  echo "  docker compose -f query-app-docker-compose.yml up" >&2
  exit 1
fi

echo "==> Catalogs"
run "SHOW CATALOGS"

echo "==> Schemas in iceberg"
run "SHOW SCHEMAS FROM iceberg"

NS="${1:-${ICEBERG_NAMESPACE:-}}"
if [ -n "$NS" ]; then
  echo "==> Tables in iceberg.\"$NS\""
  run "SHOW TABLES FROM iceberg.\"$NS\""

  TABLE="${2:-order}"
  echo "==> Row count of iceberg.\"$NS\".\"$TABLE\" (reads data files from S3)"
  run "SELECT count(*) AS orders FROM iceberg.\"$NS\".\"$TABLE\""
else
  echo "(pass a namespace to also list tables and count rows: ./smoke-test.sh <namespace> [table])"
fi

echo "OK — Trino reached Open Catalog and the Iceberg metadata."
