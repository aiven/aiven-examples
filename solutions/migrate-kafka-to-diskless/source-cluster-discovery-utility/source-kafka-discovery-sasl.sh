#!/bin/bash

# --- Source Cluster Discovery Utility for SASL Authentication ---
# This script collects information from a Kafka cluster using SASL authentication.
# It collects system information, Kafka broker configurations, consumer groups,
# and topic details. The collected data is saved to a directory.
# Example usage:
# KAFKA_USER="my-user" KAFKA_PASS="my-password" CA_PATH="/path/to/ca.pem" ./source-kafka-discovery-sasl.sh

# --- Configuration ---
BOOTSTRAP_SERVER="${KAFKA_BOOTSTRAP_SERVER:-localhost:9092}"
KAFKA_BIN_DIR="${KAFKA_BIN_DIR:-/opt/kafka/bin}"
OUTPUT_DIR="${OUTPUT_DIR:-./output}"

# Security Credentials (Pass these in or set them here)
USER="${KAFKA_USER:-admin}"
PASS="${KAFKA_PASS:-password}"
CA_PATH="${CA_PATH:-./ca.pem}" # Path to your ca.pem

# Create Output Directory if it doesn't exist
if [ ! -d "$OUTPUT_DIR" ]; then
    mkdir -p $OUTPUT_DIR
fi

# --- Setup Security Config ---
# We create a temporary properties file for the Kafka CLI tools to use
CONFIG_FILE=$(mktemp)

cat <<EOF > "$CONFIG_FILE"
security.protocol=SASL_SSL
sasl.mechanism=SCRAM-SHA-512
ssl.truststore.type=PEM
ssl.truststore.location=$CA_PATH
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required \
    username="$USER" \
    password="$PASS";
EOF

# Ensure the config file is deleted when the script exits
trap 'rm -f "$CONFIG_FILE"' EXIT

echo "Using security configuration from $CONFIG_FILE"

# --- Data Collection ---

# 1. Local System Info (No Kafka connection needed)
$KAFKA_BIN_DIR/kafka-configs.sh --version > "$OUTPUT_DIR/kafka_version.txt"
cat /etc/*-release > "$OUTPUT_DIR/linux_distribution.txt"
uname -r > "$OUTPUT_DIR/kernel_version.txt"
lscpu > "$OUTPUT_DIR/cpu_info.txt"
cat /proc/meminfo > "$OUTPUT_DIR/mem_info.txt"
sysctl -a > "$OUTPUT_DIR/kernel_settings.txt"
getconf -a > "$OUTPUT_DIR/kernel_compile_options.txt"

# 2. Remote Kafka Info (Using --command-config)
COMMON_ARGS="--bootstrap-server $BOOTSTRAP_SERVER --command-config $CONFIG_FILE"

echo "Collecting Kafka broker configurations..."
$KAFKA_BIN_DIR/kafka-configs.sh $COMMON_ARGS --describe --entity-type brokers --all > "$OUTPUT_DIR/kafka_broker_configs.txt"

echo "Collecting Consumer Groups..."
$KAFKA_BIN_DIR/kafka-consumer-groups.sh $COMMON_ARGS --all-groups --describe --timeout 180000 > "$OUTPUT_DIR/consumer_groups_source.txt"

echo "Collecting Consumer Group States..."
$KAFKA_BIN_DIR/kafka-consumer-groups.sh $COMMON_ARGS --all-groups --describe --state --timeout 180000 > "$OUTPUT_DIR/consumer_groups_state_source.txt"

echo "Collecting Topic Details..."
$KAFKA_BIN_DIR/kafka-topics.sh $COMMON_ARGS --describe > "$OUTPUT_DIR/topics_list_source.txt"

echo "Collecting Topic Offsets/Log Dirs..."
$KAFKA_BIN_DIR/kafka-log-dirs.sh $COMMON_ARGS --describe | grep logDirs > "$OUTPUT_DIR/topics_offsets_source.json"

echo "Source cluster discovery utility completed successfully."