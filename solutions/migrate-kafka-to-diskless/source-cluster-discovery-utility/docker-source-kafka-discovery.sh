#!/bin/bash

# Run source cluster discovery inside Apache Kafka container.
# Mounts the current directory so source-kafka-discovery.sh and output are on the host.
# Set KAFKA_BOOTSTRAP_SERVER to target your cluster (default: localhost:9092).

BOOTSTRAP_SERVER="${KAFKA_BOOTSTRAP_SERVER:-localhost:9092}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

docker run --rm \
  -e KAFKA_BOOTSTRAP_SERVER="$BOOTSTRAP_SERVER" \
  -v "$SCRIPT_DIR:/workspace" \
  -w /workspace \
  apache/kafka:latest \
  bash /workspace/source-kafka-discovery.sh
