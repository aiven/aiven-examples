#!/usr/bin/env bash
#
# Cluster Throughput Discovery Script
# Uses Kafka binary scripts to estimate average throughput from consumer group
# offset deltas (messages/sec per group; bytes/sec when AVG_MESSAGE_BYTES is set).
#
# Usage:
#   export BOOTSTRAP_SERVER="your-bootstrap:9092"
#   ./cluster-throughput-discovery.sh
# Optional: SAMPLE_INTERVAL_SEC=15 (default 10) to sample consumer offsets over 15s
# Optional: AVG_MESSAGE_BYTES=1024 to get bytes/sec in output
#

set -e

BOOTSTRAP_SERVER="${BOOTSTRAP_SERVER:-<STRIMZI-BOOTSTRAP-SERVER>:<STRIMZI-PORT>}"
OUTPUT_DIR="${OUTPUT_DIR:-.}"
TIMEOUT_MS="${TIMEOUT_MS:-300000}"
SAMPLE_INTERVAL_SEC="${SAMPLE_INTERVAL_SEC:-10}"
# Optional: average message size in bytes; when set, bytes/sec = messages_per_sec * AVG_MESSAGE_BYTES
AVG_MESSAGE_BYTES="${AVG_MESSAGE_BYTES:-0}"

# #region agent log
DEBUG_LOG="/Users/maja.schermuly/aiven/aiven-examples/solutions/kafka-throughput-discovery/.cursor/debug-a277fa.log"
[ -d "$(dirname "$DEBUG_LOG")" ] || DEBUG_LOG="$OUTPUT_DIR/debug-a277fa.log"
_debug_log() { echo "{\"sessionId\":\"a277fa\",\"location\":\"cluster-throughput-discovery.sh:$1\",\"message\":\"$2\",\"data\":{$3},\"timestamp\":$(($(date +%s)*1000)),\"hypothesisId\":\"$4\"}" >> "$DEBUG_LOG"; }
_debug_log "22" "AVG_MESSAGE_BYTES and OUTPUT_DIR" "\"AVG_MESSAGE_BYTES\":\"$AVG_MESSAGE_BYTES\",\"OUTPUT_DIR\":\"$OUTPUT_DIR\"" "A,E"
# #endregion

# Optional: path to client security config (SSL/SASL) for --command-config
COMMAND_CONFIG_ARGS=()
if [ -n "${KAFKA_CLIENT_CONFIG:-}" ] && [ -f "$KAFKA_CLIENT_CONFIG" ]; then
  COMMAND_CONFIG_ARGS=(--command-config "$KAFKA_CLIENT_CONFIG")
fi

echo "Throughput discovery using bootstrap server: $BOOTSTRAP_SERVER"
echo "Output directory: $OUTPUT_DIR"
echo "Sample interval: ${SAMPLE_INTERVAL_SEC}s"
[ -n "$AVG_MESSAGE_BYTES" ] && [ "$AVG_MESSAGE_BYTES" -gt 0 ] 2>/dev/null && echo "Avg message size: ${AVG_MESSAGE_BYTES} bytes (bytes/sec will be computed)"
mkdir -p "$OUTPUT_DIR"

# --- Consumer group throughput: sample offsets twice and compute rate ---
echo "Sampling consumer group offsets (first sample)..."
./bin/kafka-consumer-groups.sh --all-groups --describe --bootstrap-server "$BOOTSTRAP_SERVER" "${COMMAND_CONFIG_ARGS[@]}" --timeout "$TIMEOUT_MS" > "$OUTPUT_DIR/consumer_groups_offsets_sample1.txt" 2>&1

echo "Waiting ${SAMPLE_INTERVAL_SEC}s before second sample..."
sleep "$SAMPLE_INTERVAL_SEC"

echo "Sampling consumer group offsets (second sample)..."
./bin/kafka-consumer-groups.sh --all-groups --describe --bootstrap-server "$BOOTSTRAP_SERVER" "${COMMAND_CONFIG_ARGS[@]}" --timeout "$TIMEOUT_MS" > "$OUTPUT_DIR/consumer_groups_offsets_sample2.txt" 2>&1

# --- Compute offset deltas and approximate messages/sec per group ---
# kafka-consumer-groups --describe columns: GROUP TOPIC PARTITION CURRENT-OFFSET LOG-END-OFFSET LAG ...
echo "Computing throughput summary..."
THROUGHPUT_SUMMARY="$OUTPUT_DIR/throughput_summary.txt"
S1="$OUTPUT_DIR/consumer_groups_offsets_sample1.txt"
S2="$OUTPUT_DIR/consumer_groups_offsets_sample2.txt"
if command -v awk >/dev/null 2>&1 && [ -f "$S1" ] && [ -f "$S2" ]; then
  awk -v interval="$SAMPLE_INTERVAL_SEC" -v avg_bytes="$AVG_MESSAGE_BYTES" -v s1="$S1" -v s2="$S2" '
    FNR==1 || /^GROUP / { next }
    FILENAME==s1 { key=$1","$2","$3; o1[key]=$4; next }
    FILENAME==s2 {
      key=$1","$2","$3
      if (key in o1 && $4 ~ /^[0-9]+$/ && o1[key] ~ /^[0-9]+$/) {
        delta = $4 - o1[key]
        if (delta >= 0) group_sum[$1] += delta
      }
      next
    }
    END {
      print "GROUP,MESSAGES_DELTA,MESSAGES_PER_SEC,BYTES_PER_SEC"
      for (g in group_sum)
        if (group_sum[g] > 0) {
          mps = group_sum[g] / interval
          bps = (avg_bytes > 0) ? (mps * avg_bytes) : "N/A"
          print g "," group_sum[g] "," mps "," bps
        }
    }
  ' "$S1" "$S2" 2>/dev/null > "$OUTPUT_DIR/throughput_by_group.csv" || true
fi

# #region agent log
csv_exists="false"; [ -f "$OUTPUT_DIR/throughput_by_group.csv" ] && csv_exists="true"
csv_lines=0; [ -f "$OUTPUT_DIR/throughput_by_group.csv" ] && csv_lines=$(wc -l < "$OUTPUT_DIR/throughput_by_group.csv")
_debug_log "76" "after awk: csv exists and line count" "\"csv_exists\":$csv_exists,\"csv_lines\":$csv_lines\"" "B,C"
# #endregion

{
  echo "Throughput discovery summary — $(date -Iseconds 2>/dev/null || date)"
  echo "Bootstrap server: $BOOTSTRAP_SERVER"
  echo "Sample interval: ${SAMPLE_INTERVAL_SEC}s"
  echo "---"
  if [ -f "$OUTPUT_DIR/throughput_by_group.csv" ]; then
    echo "Per-group throughput (messages/sec, bytes/sec when AVG_MESSAGE_BYTES set):"
    cat "$OUTPUT_DIR/throughput_by_group.csv"
    echo "---"
    TOTAL_MPS=$(awk -F, 'NR>1 && $3>0 { sum += $3 } END { print sum+0 }' "$OUTPUT_DIR/throughput_by_group.csv")
    echo "Total cluster consumption: ${TOTAL_MPS} messages/sec"
    # #region agent log
    _bytes_check_nonnumeric=0; [ -n "$AVG_MESSAGE_BYTES" ] && [ "$AVG_MESSAGE_BYTES" -gt 0 ] 2>/dev/null || _bytes_check_nonnumeric=1
    _debug_log "92" "summary bytes branch" "\"AVG_MESSAGE_BYTES\":\"$AVG_MESSAGE_BYTES\",\"bytes_branch_taken\":$((1-_bytes_check_nonnumeric))" "D"
    # #endregion
    if [ -n "$AVG_MESSAGE_BYTES" ] && [ "$AVG_MESSAGE_BYTES" -gt 0 ] 2>/dev/null; then
      TOTAL_BPS=$(awk -F, 'NR>1 && $4 ~ /^[0-9]+\.?[0-9]*$/ { sum += $4+0 } END { print sum+0 }' "$OUTPUT_DIR/throughput_by_group.csv")
      # #region agent log
      _debug_log "96" "bytes/sec computed" "\"TOTAL_BPS\":\"$TOTAL_BPS\"" "D"
      # #endregion
      echo "Total cluster consumption: ${TOTAL_BPS} bytes/sec (avg message size: ${AVG_MESSAGE_BYTES} bytes)"
    fi
  else
    echo "Raw offset samples: consumer_groups_offsets_sample1.txt, consumer_groups_offsets_sample2.txt"
    echo "Compute throughput manually: (offset2 - offset1) / ${SAMPLE_INTERVAL_SEC} per partition, then sum per group."
  fi
  echo "---"
  echo "Details: consumer_groups_offsets_sample1.txt, consumer_groups_offsets_sample2.txt"
} > "$THROUGHPUT_SUMMARY"

echo "Done. Throughput summary: $THROUGHPUT_SUMMARY"
