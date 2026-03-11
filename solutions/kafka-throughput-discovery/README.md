# Cluster Throughput Discovery

This utility estimates average throughput of your Kafka cluster by sampling consumer group offsets twice over a configurable interval and computing messages/sec and bytes/sec per group (when you set average message size).

## Overview

The script uses Kafka's `kafka-consumer-groups.sh` to take two snapshots of consumer group offsets, then computes offset deltas to derive approximate consumption rate per group and total cluster consumption. For clusters that use SSL or SASL, you provide a client config file (`config.properties`) and point the script at it.

**Recommended way to run:** use the provided Docker image so you don't need Kafka CLI tools installed locally.

## Prerequisites

- Docker (to build and run the container)
- Network access to your Kafka cluster
- For secured clusters: CA and client credentials (certificates or SASL username/password) and a `config.properties` file (see below)

## Running via Docker

### 1. Build the image

From the `kafka-throughput-discovery` directory:

```bash
docker build -t kafka-throughput-discovery .
```

### 2. Prepare client config (SSL or SASL clusters only)

If your cluster uses **plaintext** (no auth), you can skip this step and only set `BOOTSTRAP_SERVER` when running the container.

For **SSL (mTLS)** or **SASL**:

1. Copy the example config and edit it:

   ```bash
   cp config.properties.example config.properties
   ```

2. In `config.properties`, **pick one** of the three options (SSL with JKS/PKCS12, SASL over TLS, or SASL plaintext) and uncomment the matching block. Replace placeholders with your CA path, keystore/truststore paths and passwords, or SASL username/password.  
   You do **not** set `bootstrap.servers` in this file — the script uses the `BOOTSTRAP_SERVER` environment variable.

3. **Paths inside the container:** when running with Docker, the script reads `config.properties` from a mounted path (e.g. `/config/config.properties`). Any paths in `config.properties` (e.g. `ssl.truststore.location`, `ssl.keystore.location`, `ssl.truststore.location`) must be valid **inside** the container. So use paths like `/config/ca.pem`, `/config/client.truststore.jks`, etc., and mount the directory that contains both `config.properties` and the cert files (see below).

### 3. Run the container

**Plaintext cluster (no auth):**

```bash
docker run --rm \
  -e BOOTSTRAP_SERVER="your-bootstrap.example.com:9092" \
  -e AVG_MESSAGE_BYTES=1024 \
  -v "$(pwd)/output:/output" \
  kafka-throughput-discovery
```

**Secured cluster (SSL or SASL):** mount the directory that contains `config.properties` and your certs (e.g. `ca.pem`, `client.truststore.jks`, `client.keystore.p12`) and pass the config path and bootstrap server:

```bash
docker run --rm \
  -e BOOTSTRAP_SERVER="your-bootstrap.example.com:9093" \
  -e KAFKA_CLIENT_CONFIG=/config/config.properties \
  -e AVG_MESSAGE_BYTES=1024 \
  -v "$(pwd)/output:/output" \
  -v "$(pwd):/config:ro" \
  kafka-throughput-discovery
```

If you keep config and certs in a subfolder (e.g. `./config/`), mount that folder as `/config` and put `config.properties` and certs inside it:

```bash
docker run --rm \
  -e BOOTSTRAP_SERVER="your-bootstrap.example.com:9093" \
  -e KAFKA_CLIENT_CONFIG=/config/config.properties \
  -e AVG_MESSAGE_BYTES=1024 \
  -v "$(pwd)/output:/output" \
  -v "$(pwd)/config:/config:ro" \
  kafka-throughput-discovery
```

Results are written to `/output` inside the container; with `-v "$(pwd)/output:/output"` they appear in `./output` on your host.

## Config.properties additions

The script passes your client config to Kafka CLI tools via `--command-config`. Create `config.properties` from `config.properties.example` and add **one** of the following, depending on how your cluster is secured.

- **SSL (client cert in keystore):** set `security.protocol=SSL`, `ssl.truststore.*` and `ssl.keystore.*` (and `ssl.key.password` if needed). Use paths like `/config/client.truststore.jks` and `/config/client.keystore.p12` when running with Docker and mounting your dir as `/config`.
- **SASL over TLS:** set `security.protocol=SASL_SSL`, `ssl.truststore.location` (e.g. `/config/ca.pem`), `sasl.mechanism` (e.g. `SCRAM-SHA-256`), and `sasl.jaas.config` with your username and password.
- **SASL plaintext:** set `security.protocol=SASL_PLAINTEXT`, `sasl.mechanism`, and `sasl.jaas.config` (only on trusted networks).

Do **not** add `bootstrap.servers` in `config.properties`; the script sets the broker list via `BOOTSTRAP_SERVER`.

## Environment variables

| Variable               | Default       | Description |
| ---------------------- | ------------- | ----------- |
| `BOOTSTRAP_SERVER`     | (none; set it)| Kafka bootstrap server (host:port). |
| `OUTPUT_DIR`           | `/output`     | Directory for output files (use `/output` in Docker and mount it). |
| `KAFKA_CLIENT_CONFIG`  | (none)        | Path to client config file for SSL/SASL (e.g. `/config/config.properties` in Docker). |
| `SAMPLE_INTERVAL_SEC`  | `10`          | Seconds between the two offset samples. |
| `TIMEOUT_MS`           | `300000`      | Timeout in ms for consumer group commands. |
| `AVG_MESSAGE_BYTES`    | `0`           | Average message size in bytes; bytes/sec = messages/sec × this value. Set this for bytes/sec in the output. |

## Output

All files are written to `OUTPUT_DIR` (with Docker, typically `./output` on the host):

- `consumer_groups_offsets_sample1.txt` / `consumer_groups_offsets_sample2.txt` — raw offset snapshots
- `throughput_by_group.csv` — per-group messages delta, messages/sec, and bytes/sec (when `AVG_MESSAGE_BYTES` is set)
- `throughput_summary.txt` — human-readable summary and total cluster consumption (messages/sec and bytes/sec when `AVG_MESSAGE_BYTES` is set)

## Running without Docker

If you have Kafka CLI tools installed (e.g. under `/opt/kafka/bin`), you can run the script directly:

```bash
export BOOTSTRAP_SERVER="your-bootstrap.example.com:9092"
export AVG_MESSAGE_BYTES=1024
# For SSL/SASL:
export KAFKA_CLIENT_CONFIG=/path/to/config.properties
./cluster-throughput-discovery.sh
```

Run from a directory that contains the script and where `./bin` has the Kafka scripts, or adapt the script to use your `KAFKA_BIN_DIR`.

## Troubleshooting

- **Connection timeouts:** Check `BOOTSTRAP_SERVER` and that the container can reach the cluster (firewall, VPN).
- **SSL/SASL errors:** Ensure `config.properties` uses paths that exist inside the container (e.g. `/config/ca.pem`) and that the mounted volume contains those files. Verify credentials and CA match the cluster.
- **Empty or missing throughput_by_group.csv:** Ensure there are active consumer groups and that offsets advance between the two samples; increase `SAMPLE_INTERVAL_SEC` if needed.
