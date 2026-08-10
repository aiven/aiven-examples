#!/usr/bin/env bash
# End-to-end latency probe: every INTERVAL seconds, POST one marker event and
# poll ClickHouse until it is queryable. Appends CSV: timestamp,latency_ms.
#
# The marker's campaign_id is unique per sample, so each poll is a cheap
# count() on a LowCardinality column. Latency = POST accepted -> row visible,
# i.e. the full XADD -> XREADGROUP -> bulk insert -> merge-visible path.
#
# Env (defaults = local docker-compose):
#   APP_URL       http://localhost:8080
#   INGEST_API_KEY  (optional; sent as X-API-Key when set)
#   CH_HOST       localhost   CH_PORT 9000   CH_SECURE ""  (set CH_SECURE=--secure for Aiven)
#   CH_USER       default     CH_PASSWORD local
#   CH_DATABASE   campaign_analytics
#   INTERVAL      1           seconds between samples
#   TIMEOUT_MS    30000       give up on a sample after this
#   OUT           latency.csv
set -euo pipefail

APP_URL=${APP_URL:-http://localhost:8080}
CH_HOST=${CH_HOST:-localhost}
CH_PORT=${CH_PORT:-9000}
CH_SECURE=${CH_SECURE:-}
CH_USER=${CH_USER:-default}
CH_PASSWORD=${CH_PASSWORD:-local}
CH_DATABASE=${CH_DATABASE:-campaign_analytics}
INTERVAL=${INTERVAL:-1}
TIMEOUT_MS=${TIMEOUT_MS:-30000}
OUT=${OUT:-latency.csv}

AUTH=()
[ -n "${INGEST_API_KEY:-}" ] && AUTH=(-H "X-API-Key: ${INGEST_API_KEY}")

ch() {
  clickhouse client --host "$CH_HOST" --port "$CH_PORT" $CH_SECURE \
    --user "$CH_USER" --password "$CH_PASSWORD" --database "$CH_DATABASE" \
    --query "$1" 2>/dev/null
}

[ -f "$OUT" ] || echo "timestamp,latency_ms" > "$OUT"
echo "latency probe -> $OUT (Ctrl-C to stop)" >&2

n=0
while true; do
  n=$((n + 1))
  marker="probe-$(date +%s)-$n-$$"
  t0=$(python3 -c 'import time; print(int(time.time()*1000))')
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$APP_URL/events" \
    -H 'Content-Type: application/json' ${AUTH[@]+"${AUTH[@]}"} \
    -d "[{\"event_type\":\"probe\",\"user_id\":\"probe\",\"session_id\":\"probe\",
         \"campaign_id\":\"$marker\",\"channel\":\"direct\",\"country\":\"ID\",\"device_type\":\"probe\"}]")
  if [ "$code" != "202" ]; then
    echo "$(date -u +%FT%TZ) POST rejected ($code) - backing off" >&2
    sleep "$INTERVAL"
    continue
  fi
  while true; do
    count=$(ch "SELECT count() FROM campaign_events WHERE campaign_id = '$marker'" || echo 0)
    now=$(python3 -c 'import time; print(int(time.time()*1000))')
    if [ "${count:-0}" -ge 1 ]; then
      echo "$(date -u +%FT%TZ),$((now - t0))" >> "$OUT"
      break
    fi
    if [ $((now - t0)) -gt "$TIMEOUT_MS" ]; then
      echo "$(date -u +%FT%TZ)," >> "$OUT"   # empty latency = timed out
      echo "$(date -u +%FT%TZ) sample $marker timed out (>${TIMEOUT_MS}ms)" >&2
      break
    fi
    sleep 0.05
  done
  sleep "$INTERVAL"
done
