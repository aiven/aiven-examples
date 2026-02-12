#!/bin/bash

# --- Configuration ---
BOOTSTRAP_SERVER="${KAFKA_BOOTSTRAP_SERVER:-localhost:9092}"
KAFKA_BIN_DIR="${KAFKA_BIN_DIR:-/opt/kafka/bin}"
OUTPUT_DIR="${OUTPUT_DIR:-./output}"

# Create Output Directory if it doesn't exist
if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p $OUTPUT_DIR
fi

# --- Data Collection ---

# 1. Local System Info (No Kafka connection needed)
$KAFKA_BIN_DIR/kafka-configs.sh --version > "$OUTPUT_DIR/kafka_version.txt"
cat /etc/*-release > "$OUTPUT_DIR/linux_distribution.txt"
uname -r > "$OUTPUT_DIR/kernel_version.txt"
lscpu > "$OUTPUT_DIR/cpu_info.txt"
cat /proc/meminfo > "$OUTPUT_DIR/mem_info.txt"
sysctl -a > "$OUTPUT_DIR/kernel_settings.txt"
getconf -a > "$OUTPUT_DIR/kernel_compile_options.txt"

echo "Collecting Kafka broker configurations..."
$KAFKA_BIN_DIR/kafka-configs.sh --describe --bootstrap-server $BOOTSTRAP_SERVER --entity-type brokers --all > "$OUTPUT_DIR/kafka_broker_configs.txt"

echo "Collecting Consumer Groups from cluster..."
$KAFKA_BIN_DIR/kafka-consumer-groups.sh --all-groups --describe --bootstrap-server $BOOTSTRAP_SERVER --timeout 180000 > "$OUTPUT_DIR/consumer_groups_source.txt"

echo "Collecting Consumer Group States from cluster..."
$KAFKA_BIN_DIR/kafka-consumer-groups.sh --all-groups --describe --state --bootstrap-server $BOOTSTRAP_SERVER --timeout 180000 > "$OUTPUT_DIR/consumer_groups_state_source.txt"

echo "Collecting Topic Details from cluster..."
$KAFKA_BIN_DIR/kafka-topics.sh --describe --bootstrap-server $BOOTSTRAP_SERVER > "$OUTPUT_DIR/topics_list_source.txt"

echo "Collecting Topic Offsets from cluster..."
$KAFKA_BIN_DIR/kafka-log-dirs.sh --describe --bootstrap-server $BOOTSTRAP_SERVER | grep "logDirs" > "$OUTPUT_DIR/topics_offsets_source.json"

echo "Source cluster discovery utility completed successfully."