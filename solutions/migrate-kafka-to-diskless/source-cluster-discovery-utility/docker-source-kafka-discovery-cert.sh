#!/bin/bash

# Run source cluster discovery (mTLS/certificate) inside Apache Kafka container.
# Mounts the current directory so source-kafka-discovery-cert.sh, cert files, and output are on the host.
#
# Required: CA file, client cert, and client key in this directory (or set paths via env).
# Optional: KAFKA_BOOTSTRAP_SERVER (default localhost:9092).
#   CA_PATH (default ./ca.pem), CLIENT_CERT_PATH (default ./server.cert), CLIENT_KEY_PATH (default ./server.key).

BOOTSTRAP_SERVER="${KAFKA_BOOTSTRAP_SERVER:-localhost:9092}"
CA_PATH="${CA_PATH:-./ca.pem}"
CLIENT_CERT_PATH="${CLIENT_CERT_PATH:-./server.cert}"
CLIENT_KEY_PATH="${CLIENT_KEY_PATH:-./server.key}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Paths must be relative so they exist under the mounted directory in the container
for p in CA_PATH CLIENT_CERT_PATH CLIENT_KEY_PATH; do
  eval "val=\$$p"
  case "$val" in /*) echo "Error: $p must be relative to the script directory (e.g. ./ca.pem)." >&2; exit 1 ;; esac
done
CA_FULL="$SCRIPT_DIR/$CA_PATH"
CERT_FULL="$SCRIPT_DIR/$CLIENT_CERT_PATH"
KEY_FULL="$SCRIPT_DIR/$CLIENT_KEY_PATH"

if [ ! -f "$CA_FULL" ] || [ ! -f "$CERT_FULL" ] || [ ! -f "$KEY_FULL" ]; then
  echo "Error: Certificate files must exist in the script directory." >&2
  echo "  CA_PATH=$CA_PATH" >&2
  echo "  CLIENT_CERT_PATH=$CLIENT_CERT_PATH" >&2
  echo "  CLIENT_KEY_PATH=$CLIENT_KEY_PATH" >&2
  echo "Example: KAFKA_BOOTSTRAP_SERVER=kafka:9093 ./docker-source-kafka-discovery-cert.sh" >&2
  exit 1
fi

docker run --rm \
  -e KAFKA_BOOTSTRAP_SERVER="$BOOTSTRAP_SERVER" \
  -e CA_PATH="$CA_PATH" \
  -e CLIENT_CERT_PATH="$CLIENT_CERT_PATH" \
  -e CLIENT_KEY_PATH="$CLIENT_KEY_PATH" \
  -v "$SCRIPT_DIR:/workspace" \
  -w /workspace \
  apache/kafka:latest \
  bash /workspace/source-kafka-discovery-cert.sh
