# Source Cluster Discovery Utility

This utility collects comprehensive information from a Kafka source cluster to aid in migration planning. It gathers system information, Kafka broker configurations, consumer groups, topics, and offsets.

## Overview

The discovery utility consists of three main scripts, each designed for different authentication methods:

- **`source-kafka-discovery.sh`** - Plaintext connection (no authentication)
- **`source-kafka-discovery-cert.sh`** - Certificate-based authentication (mTLS)
- **`source-kafka-discovery-sasl.sh`** - SASL authentication (SCRAM-SHA-512)

When Kafka CLI tools are not installed locally, use the Docker wrappers (they run the same logic inside an `apache/kafka:latest` container and mount the current directory so output appears in `./output`):

- **`docker-source-kafka-discovery.sh`** - Plaintext
- **`docker-source-kafka-discovery-cert.sh`** - mTLS (certificate paths must be relative to the script directory)
- **`docker-source-kafka-discovery-sasl.sh`** - SASL (requires `KAFKA_USER` and `KAFKA_PASS`)

## Prerequisites

- Kafka CLI tools installed (typically in `/opt/kafka/bin`)
- Network access to the Kafka cluster
- Appropriate authentication credentials (if using SSL or SASL)

## Usage

### Plaintext Connection (No Authentication)

For clusters without authentication:

```bash
./source-kafka-discovery.sh
```

Or with custom bootstrap server:

```bash
KAFKA_BOOTSTRAP_SERVER="localhost:9092" ./source-kafka-discovery.sh
```

**Docker (no local Kafka CLI)**

```bash
KAFKA_BOOTSTRAP_SERVER="kafka.example.com:9092" ./docker-source-kafka-discovery.sh
```

### Certificate Authentication (mTLS)

For clusters using certificate-based authentication:

```bash
KAFKA_BOOTSTRAP_SERVER="kafka.example.com:12693" \
  CA_PATH="./ca.pem" \
  CLIENT_CERT_PATH="./server.cert" \
  CLIENT_KEY_PATH="./server.key" \
  ./source-kafka-discovery-cert.sh
```

**Docker (no local Kafka CLI)**  
Certificate paths must be relative to the script directory (e.g. `./ca.pem`, `secrets/server.cert`). Files must exist in that directory.

```bash
KAFKA_BOOTSTRAP_SERVER="kafka.example.com:9092" \
  CA_PATH=secrets/ca.pem \
  CLIENT_CERT_PATH=secrets/server.cert \
  CLIENT_KEY_PATH=secrets/server.key \
  ./docker-source-kafka-discovery-cert.sh
```

**Required Files:**

- `ca.pem` - CA certificate (default: `./ca.pem`)
- `server.cert` - Client certificate (default: `./server.cert`)
- `server.key` - Client private key (default: `./server.key`)

### SASL Authentication (SCRAM-SHA-512)

For clusters using SASL/SCRAM authentication:

```bash
KAFKA_USER="avnadmin" \
  KAFKA_PASS="your-password" \
  KAFKA_BOOTSTRAP_SERVER="kafka.example.com:9092" \
  CA_PATH=secrets/ca.pem \
  ./source-kafka-discovery-sasl.sh
```

**Docker (no local Kafka CLI)**  
`KAFKA_USER` and `KAFKA_PASS` are required (no defaults).

```bash
KAFKA_BOOTSTRAP_SERVER="kafka.example.com:9092" \
  KAFKA_USER="my-user" \
  KAFKA_PASS="my-password" \
  CA_PATH=secrets/ca.pem \
  ./docker-source-kafka-discovery-sasl.sh
```

**Required Files:**

- `ca.pem` - CA certificate (default: `./ca.pem`)

## Configuration Options

All scripts support the following environment variables:

| Variable                 | Default          | Description                                  |
| ------------------------ | ---------------- | -------------------------------------------- |
| `KAFKA_BOOTSTRAP_SERVER` | `localhost:9092` | Kafka bootstrap server address               |
| `KAFKA_BIN_DIR`          | `/opt/kafka/bin` | Path to Kafka CLI tools directory            |
| `OUTPUT_DIR`             | `./output`       | Directory where collected data will be saved |

### Certificate Script Additional Options

| Variable           | Default         | Description                     |
| ------------------ | --------------- | ------------------------------- |
| `CA_PATH`          | `./ca.pem`      | Path to CA certificate file     |
| `CLIENT_CERT_PATH` | `./server.cert` | Path to client certificate file |
| `CLIENT_KEY_PATH`  | `./server.key`  | Path to client private key file |

### SASL Script Additional Options

| Variable     | Default    | Description                 |
| ------------ | ---------- | --------------------------- |
| `KAFKA_USER` | `admin`    | SASL username               |
| `KAFKA_PASS` | `password` | SASL password               |
| `CA_PATH`    | `./ca.pem` | Path to CA certificate file |

## Output

All collected data is saved to the `OUTPUT_DIR` (default: `./output`).

### System information (plaintext and SASL scripts only)

- `kafka_version.txt` - Kafka version information
- `linux_distribution.txt` - Linux distribution details
- `kernel_version.txt` - Kernel version
- `cpu_info.txt` - CPU information
- `mem_info.txt` - Memory information
- `kernel_settings.txt` - Kernel settings (sysctl)
- `kernel_compile_options.txt` - Kernel compile options

The certificate script (`source-kafka-discovery-cert.sh`) only writes `kafka_version.txt`, `cpu_info.txt`, and `mem_info.txt` for system info.

### Kafka cluster information

- `kafka_broker_configs.txt` - Broker configurations
- `consumer_groups_source.txt` - Consumer groups details
- `consumer_groups_state_source.txt` - Consumer groups state (plaintext and SASL only; not produced by the cert script)
- `topics_list_source.txt` - Topic details and configurations
- `topics_offsets_source.json` - Topic offsets and log directory information

## Running a local Kafka (for testing)

A `docker-compose.yaml` is provided to start a single-node Kafka (plaintext on port 9092). Use it to test the discovery scripts without a real cluster:

```bash
docker compose up -d
# Wait for the broker to be healthy, then:
KAFKA_BOOTSTRAP_SERVER="localhost:9092" ./source-kafka-discovery.sh
# or
KAFKA_BOOTSTRAP_SERVER="localhost:9092" ./docker-source-kafka-discovery.sh
```

## Notes

- The certificate script (`source-kafka-discovery-cert.sh`) validates that the client certificate and key match before proceeding, standardizes PEMs, and builds a combined keystore for the Kafka CLI.
- All scripts create the output directory automatically if it doesn't exist.
- Temporary configuration files are automatically cleaned up on script exit.
- The scripts use a timeout of 180 seconds (3 minutes) for consumer group operations.

## Troubleshooting

1. **Certificate validation errors**: Ensure your certificate and key files match and are in PEM format
2. **Connection timeouts**: Verify the `KAFKA_BOOTSTRAP_SERVER` address and port are correct
3. **Authentication failures**: Double-check credentials and certificate paths
4. **Missing Kafka tools**: Ensure `KAFKA_BIN_DIR` points to the correct directory containing Kafka CLI tools
