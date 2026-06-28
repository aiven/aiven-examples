# live-orders

A long-running Kafka producer that continuously streams mock ecommerce orders
at a configurable rate until stopped. It's the "live" data source for the
[aiven-trino-mcp-federation](../PLAN-SIMPLIFIED.md) demo:

```
live-orders ──► Aiven Kafka ──(Kafka Connect: Iceberg sink)──► Iceberg / S3 ──► Trino
```

Each order is stamped with the current time, so the data is genuinely live
(unlike the one-shot batch producer in `aiven-iceberg-tutorial`, which this is
adapted from — that folder is left untouched).

## Configuration

All configuration is via environment variables. **For Aiven Apps these are set
in the Aiven Apps setup (env vars / secrets) — nothing is baked into the image
and no secret is committed to git.** For local dev, copy `.env.example` to `.env`
and `source` it.

| Variable | Required | Default | Notes |
|----------|----------|---------|-------|
| `KAFKA_SERVICE_URI` | yes | — | SASL_SSL broker `host:port` (Aiven Console → Connection info, auth "SASL"). |
| `KAFKA_USERNAME` | yes | — | e.g. `avnadmin`. |
| `KAFKA_PASSWORD` | yes | — | Kafka SASL password (secret). |
| `KAFKA_TOPIC` | no | `order` | Target topic. Must match the Iceberg sink's source topic. |
| `ORDERS_PER_MINUTE` | no | `100` | Emission rate; one order every `60s / rate`. |

## Run locally

```bash
cp .env.example .env      # fill in your Kafka values
source .env
go run .
```

You'll see periodic progress logs. Stop with Ctrl-C (SIGINT) — the producer
shuts down gracefully and reports how many orders it sent. It also handles
SIGTERM, which is how Aiven Apps stops a worker.

## Build & run the container

Via Compose (reads `.env`):

```bash
docker compose -f live-orders-docker-compose.yml up --build
```

Or build the image directly:

```bash
docker build -f Containerfile -t live-orders .
# or: podman build -f Containerfile -t live-orders .
```

The image is a static binary on a distroless base, with no inbound port (it's a
pure producer). Deploy it to Aiven Apps as a **long-running worker** (via the
`live-orders-docker-compose.yml` recipe) and supply the environment variables
above in the Aiven Apps configuration.

## Tests

Unit tests (no Kafka needed — the produce path uses sarama's mock producer):

```bash
go test ./...
```

Covers order generation invariants, the rate→interval math, message
construction, and a mocked produce round-trip.

## Notes

- **Connection:** SASL_SSL + SCRAM-SHA-512, trusting the public Let's Encrypt CA
  via system roots — no project CA file or client cert needed.
- **Order schema** matches the `aiven-iceberg-tutorial` producer, so the existing
  Iceberg sink schema works unchanged.
- **Freshness:** orders reach Iceberg through the Kafka→Iceberg sink, which
  commits on an interval, so downstream queries see *near*-real-time data.
