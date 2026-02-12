#!/bin/bash

# Run source cluster discovery (SASL/SCRAM-SHA-512) inside Apache Kafka container.
# Mounts the current directory so source-kafka-discovery-sasl.sh, CA file, and output are on the host.
#
# Required: KAFKA_USER, KAFKA_PASS, and a CA file (default ./ca.pem in this directory).
# Optional: KAFKA_BOOTSTRAP_SERVER (default localhost:9092), CA_PATH (default ./ca.pem).

BOOTSTRAP_SERVER="${KAFKA_BOOTSTRAP_SERVER:-localhost:9092}"
KAFKA_USER="${KAFKA_USER:-}"
KAFKA_PASS="${KAFKA_PASS:-}"
CA_PATH="${CA_PATH:-./ca.pem}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "$KAFKA_USER" ] || [ -z "$KAFKA_PASS" ]; then
  echo "Error: KAFKA_USER and KAFKA_PASS must be set for SASL authentication." >&2
  echo "Example: KAFKA_USER=my-user KAFKA_PASS=my-password ./docker-source-kafka-discovery-sasl.sh" >&2
  exit 1
fi

docker run --rm \
  -e KAFKA_BOOTSTRAP_SERVER="$BOOTSTRAP_SERVER" \
  -e KAFKA_USER="$KAFKA_USER" \
  -e KAFKA_PASS="$KAFKA_PASS" \
  -e CA_PATH="$CA_PATH" \
  -v "$SCRIPT_DIR:/workspace" \
  -w /workspace \
  apache/kafka:latest \
  bash /workspace/source-kafka-discovery-sasl.sh
