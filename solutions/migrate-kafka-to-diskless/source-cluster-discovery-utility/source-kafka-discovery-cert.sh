#!/bin/bash

# --- Configuration ---
BOOTSTRAP_SERVER="${KAFKA_BOOTSTRAP_SERVER:-localhost:9092}"
KAFKA_BIN_DIR="${KAFKA_BIN_DIR:-/opt/kafka/bin}"
OUTPUT_DIR="${OUTPUT_DIR:-./output}"

# Path to your Certificate Files
CA_PATH="${CA_PATH:-./ca.pem}"
CLIENT_CERT_PATH="${CLIENT_CERT_PATH:-./server.cert}"
CLIENT_KEY_PATH="${CLIENT_KEY_PATH:-./server.key}"

mkdir -p "$OUTPUT_DIR"

# --- Advanced PEM Standardization ---

echo "Validating and Standardizing Certificates..."

# Check if key and cert match
CERT_HASH=$(openssl x509 -noout -modulus -in "$CLIENT_CERT_PATH" | openssl md5)
KEY_HASH=$(openssl rsa -noout -modulus -in "$CLIENT_KEY_PATH" | openssl md5)

if [ "$CERT_HASH" != "$KEY_HASH" ]; then
    echo "ERROR: Client certificate and Key do not match!"
    exit 1
fi

CLEAN_CA=$(mktemp)
CLEAN_KEY=$(mktemp)
COMBINED_KEYSTORE=$(mktemp)

# 1. Standardize the CA
openssl x509 -in "$CA_PATH" -out "$CLEAN_CA"

# 2. Standardize the Key to strictly formatted PKCS#8
# We use -outform PEM to ensure no extra headers/text are included
openssl pkcs8 -topk8 -inform PEM -outform PEM -nocrypt -in "$CLIENT_KEY_PATH" -out "$CLEAN_KEY"

# 3. Create Combined Keystore (Private Key + Client Cert + Intermediate/Root CA)
# Kafka PEM Keystores via 'location' expect the Key and Cert(s) in the same file.
cat "$CLEAN_KEY" "$CLIENT_CERT_PATH" "$CLEAN_CA" > "$COMBINED_KEYSTORE"

# --- Setup Security Config ---
CONFIG_FILE=$(mktemp)

# Setup Security Config
# NOTE: We use ssl.keystore.location (path to combined file) instead of ssl.keystore.key (raw content)
cat <<EOF > "$CONFIG_FILE"
security.protocol=SSL
ssl.truststore.type=PEM
ssl.truststore.location=$(realpath "$CLEAN_CA")
ssl.keystore.type=PEM
ssl.keystore.location=$COMBINED_KEYSTORE
ssl.endpoint.identification.algorithm=https
EOF

# Ensure cleanup
trap 'rm -f "$CONFIG_FILE" "$CLEAN_CA" "$CLEAN_KEY" "$COMBINED_KEYSTORE"' EXIT

echo "Using Certificate Authentication (mTLS) with Kafka 4.0.0..."
echo "Config file generated at: $CONFIG_FILE"

# --- Data Collection ---
COMMON_ARGS="--bootstrap-server $BOOTSTRAP_SERVER --command-config $CONFIG_FILE"

# Helper function
safe_run() {
    local cmd_name=$(basename "$1") # Extract command name for cleaner logs
    if [ -f "$1" ]; then
        echo "Running $cmd_name..."
        "$@" > "$OUTPUT_DIR/$2" 2>&1
    else
        echo "Warning: $1 command not found. Skipping $2."
    fi
}

# 1. Local System Info
$KAFKA_BIN_DIR/kafka-configs.sh --version > "$OUTPUT_DIR/kafka_version.txt"
lscpu > "$OUTPUT_DIR/cpu_info.txt"
cat /proc/meminfo > "$OUTPUT_DIR/mem_info.txt"

# 2. Remote Kafka Info
echo "Collecting Kafka broker configurations..."
$KAFKA_BIN_DIR/kafka-configs.sh $COMMON_ARGS --describe --entity-type brokers --all > "$OUTPUT_DIR/kafka_broker_configs.txt"

echo "Collecting Consumer Groups..."
$KAFKA_BIN_DIR/kafka-consumer-groups.sh $COMMON_ARGS --all-groups --describe --timeout 180000 > "$OUTPUT_DIR/consumer_groups_source.txt"

echo "Collecting Topic Details..."
$KAFKA_BIN_DIR/kafka-topics.sh $COMMON_ARGS --describe > "$OUTPUT_DIR/topics_list_source.txt"

echo "Collecting Topic Offsets/Log Dirs..."
$KAFKA_BIN_DIR/kafka-log-dirs.sh $COMMON_ARGS --describe | grep logDirs > "$OUTPUT_DIR/topics_offsets_source.json"

echo "Source cluster discovery utility completed successfully."