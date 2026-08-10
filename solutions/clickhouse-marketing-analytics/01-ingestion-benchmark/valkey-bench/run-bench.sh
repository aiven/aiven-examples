#!/usr/bin/env bash
# Valkey-path mini-benchmark orchestrator. Against a RUNNING ingest service in
# valkey mode (INGEST_BUFFER=valkey), it:
#   1. starts the end-to-end latency probe (latency-probe.sh)
#   2. samples GET /stats every STATS_INTERVAL seconds -> stats.csv
#   3. drives load with k6 (shared/loadgen/k6-events.js), SCENARIO=steady|burst
#   4. optionally retunes batch geometry mid-run (RETUNE_AT / RETUNE_BODY)
#   5. prints a summary: accepted rate, flusher throughput, latency p50/p99
#
# Env:
#   APP_URL           http://localhost:8080
#   INGEST_API_KEY    (optional)
#   SCENARIO          steady | burst        (default steady)
#   OUTDIR            ./results/<timestamp> (default)
#   STATS_INTERVAL    5
#   RETUNE_AT         seconds into the run to PUT /config ("" = never)
#   RETUNE_BODY       '{"batch_size":50000,"flush_interval_ms":1000}'
#   plus the CH_* vars latency-probe.sh needs (see its header)
set -euo pipefail
cd "$(dirname "$0")"

APP_URL=${APP_URL:-http://localhost:8080}
SCENARIO=${SCENARIO:-steady}
STATS_INTERVAL=${STATS_INTERVAL:-5}
RETUNE_AT=${RETUNE_AT:-}
RETUNE_BODY=${RETUNE_BODY:-'{"batch_size":50000,"flush_interval_ms":1000}'}
OUTDIR=${OUTDIR:-results/$(date +%Y%m%d-%H%M%S)-$SCENARIO}
K6_SCRIPT=../../shared/loadgen/k6-events.js

AUTH=()
[ -n "${INGEST_API_KEY:-}" ] && AUTH=(-H "X-API-Key: ${INGEST_API_KEY}")

command -v k6 >/dev/null || { echo "k6 not found (brew install k6)"; exit 1; }
command -v clickhouse >/dev/null || { echo "clickhouse client not found"; exit 1; }
curl -sf -m 5 "$APP_URL/actuator/health" >/dev/null || { echo "service not reachable at $APP_URL"; exit 1; }
curl -sf -m 5 ${AUTH[@]+"${AUTH[@]}"} "$APP_URL/stats" | grep -q '"mode":"valkey"' \
  || { echo "service is not in valkey mode (GET /stats)"; exit 1; }

mkdir -p "$OUTDIR"
echo "results -> $OUTDIR"
curl -s ${AUTH[@]+"${AUTH[@]}"} "$APP_URL/stats" > "$OUTDIR/stats-before.json"

# 1. latency probe
OUT="$OUTDIR/latency.csv" APP_URL="$APP_URL" ./latency-probe.sh 2> "$OUTDIR/probe.log" &
PROBE_PID=$!

# 2. stats sampler
(
  echo "timestamp,rows_flushed,batches,errors,stream_length,pending,batch_size,flush_interval_ms" > "$OUTDIR/stats.csv"
  while true; do
    s=$(curl -s -m 5 ${AUTH[@]+"${AUTH[@]}"} "$APP_URL/stats" || true)
    [ -n "$s" ] && echo "$(date -u +%FT%TZ),$(echo "$s" | jq -r \
      '[.flusher.rows_flushed // 0, .flusher.batches // 0, .flusher.errors // 0,
        .stream.length, .stream.pending, .tuning.batch_size, .tuning.flush_interval_ms] | @csv' | tr -d '"')" \
      >> "$OUTDIR/stats.csv"
    sleep "$STATS_INTERVAL"
  done
) &
SAMPLER_PID=$!

# 4. optional mid-run retune
if [ -n "$RETUNE_AT" ]; then
  (
    sleep "$RETUNE_AT"
    echo "== retuning at t+${RETUNE_AT}s: $RETUNE_BODY"
    curl -s -X PUT "$APP_URL/config" -H 'Content-Type: application/json' ${AUTH[@]+"${AUTH[@]}"} -d "$RETUNE_BODY"
    echo
  ) &
fi

cleanup() { kill "$PROBE_PID" "$SAMPLER_PID" 2>/dev/null || true; wait "$PROBE_PID" "$SAMPLER_PID" 2>/dev/null || true; }
trap cleanup EXIT

# 3. drive load
echo "== k6 $SCENARIO run"
k6 run -e BASE_URL="$APP_URL" -e SCENARIO="$SCENARIO" \
  ${INGEST_API_KEY:+-e API_KEY="$INGEST_API_KEY"} \
  --summary-export "$OUTDIR/k6-summary.json" "$K6_SCRIPT" | tee "$OUTDIR/k6.log"

sleep 5   # let the flusher drain the tail
cleanup
curl -s ${AUTH[@]+"${AUTH[@]}"} "$APP_URL/stats" > "$OUTDIR/stats-after.json"

# 5. summary
echo
echo "================ valkey mini-benchmark: $SCENARIO ================"
jq -r '"events accepted : " + (.metrics.events_accepted.count // 0 | tostring)' "$OUTDIR/k6-summary.json" 2>/dev/null || true
before=$(jq -r '.flusher.rows_flushed // 0' "$OUTDIR/stats-before.json")
after=$(jq -r '.flusher.rows_flushed // 0' "$OUTDIR/stats-after.json")
echo "rows flushed    : $((after - before)) (this run)"
jq -r '"stream backlog  : length=" + (.stream.length|tostring) + " pending=" + (.stream.pending|tostring)' "$OUTDIR/stats-after.json"
awk -F, 'NR>1 && $2!="" {a[n++]=$2} END {
  if (n==0) { print "latency         : no samples"; exit }
  asort_impl = ""; # portable sort
  for (i=0;i<n;i++) for (j=i+1;j<n;j++) if (a[j]<a[i]) { t=a[i]; a[i]=a[j]; a[j]=t }
  printf "latency e2e     : p50=%dms p99=%dms (n=%d)\n", a[int(n*0.50)], a[int(n*0.99)], n
}' "$OUTDIR/latency.csv"
echo "raw data        : $OUTDIR/"
echo "=================================================================="
