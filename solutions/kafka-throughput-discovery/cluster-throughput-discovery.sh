#!/usr/bin/env bash
#
# Cluster Throughput Discovery Script
# Uses Kafka binary scripts to estimate average throughput from consumer group
# offset deltas (messages/sec per group). Optionally can run producer/consumer
# perf tests if a test topic is provided.
#
# Usage:
#   export BOOTSTRAP_SERVER="your-bootstrap:9092"
#   ./cluster-throughput-discovery.sh
# Optional: SAMPLE_INTERVAL_SEC=15 (default 10) to sample consumer offsets over 15s
# Optional: TEST_TOPIC="perf-test" to run producer/consumer perf tests (requires topic)
#

set -e

BOOTSTRAP_SERVER="${BOOTSTRAP_SERVER:-<STRIMZI-BOOTSTRAP-SERVER>:<STRIMZI-PORT>}"
OUTPUT_DIR="${OUTPUT_DIR:-.}"
TIMEOUT_MS="${TIMEOUT_MS:-300000}"
SAMPLE_INTERVAL_SEC="${SAMPLE_INTERVAL_SEC:-10}"
# Optional: average message size in bytes; when set, bytes/sec = messages_per_sec * AVG_MESSAGE_BYTES
AVG_MESSAGE_BYTES="${AVG_MESSAGE_BYTES:-0}"

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
    if [ -n "$AVG_MESSAGE_BYTES" ] && [ "$AVG_MESSAGE_BYTES" -gt 0 ] 2>/dev/null; then
      TOTAL_BPS=$(awk -F, 'NR>1 && $4 ~ /^[0-9]+$/ { sum += $4 } END { print sum+0 }' "$OUTPUT_DIR/throughput_by_group.csv")
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

# --- Optional: producer/consumer perf test (if TEST_TOPIC set and scripts exist) ---
if [ -n "${TEST_TOPIC:-}" ]; then
  if [ -f ./bin/kafka-producer-perf-test.sh ]; then
    echo "Running producer perf test on topic: $TEST_TOPIC (10k messages, 1KB each)..."
    if [ -n "${KAFKA_CLIENT_CONFIG:-}" ] && [ -f "$KAFKA_CLIENT_CONFIG" ]; then
      ./bin/kafka-producer-perf-test.sh \
        --topic "$TEST_TOPIC" \
        --num-records 10000 \
        --record-size 1024 \
        --throughput 10000 \
        --producer.config "$KAFKA_CLIENT_CONFIG" \
        > "$OUTPUT_DIR/producer_perf_test.txt" 2>&1 || true
    else
      ./bin/kafka-producer-perf-test.sh \
        --topic "$TEST_TOPIC" \
        --num-records 10000 \
        --record-size 1024 \
        --throughput 10000 \
        --producer-props bootstrap.servers="$BOOTSTRAP_SERVER" \
        > "$OUTPUT_DIR/producer_perf_test.txt" 2>&1 || true
    fi
  fi
  if [ -f ./bin/kafka-consumer-perf-test.sh ]; then
    echo "Running consumer perf test on topic: $TEST_TOPIC..."
    if [ -n "${KAFKA_CLIENT_CONFIG:-}" ] && [ -f "$KAFKA_CLIENT_CONFIG" ]; then
      ./bin/kafka-consumer-perf-test.sh \
        --topic "$TEST_TOPIC" \
        --consumer.config "$KAFKA_CLIENT_CONFIG" \
        --messages 10000 \
        > "$OUTPUT_DIR/consumer_perf_test.txt" 2>&1 || true
    else
      ./bin/kafka-consumer-perf-test.sh \
        --topic "$TEST_TOPIC" \
        --bootstrap-server "$BOOTSTRAP_SERVER" \
        --messages 10000 \
        > "$OUTPUT_DIR/consumer_perf_test.txt" 2>&1 || true
    fi
  fi
fi
