# live-orders

A long-running worker that continuously writes mock ecommerce orders into an
**Aiven for PostgreSQL** table at a configurable rate until stopped. It's the
"live" data source for the [aiven-trino-iceberg-agent](../README.md) demo:

```
live-orders ──► Aiven PostgreSQL ──(Debezium CDC source)──► Aiven Kafka ──(Iceberg sink)──► Iceberg / S3 ──► Trino
```

Besides **INSERT**ing new orders (always status `PENDING`), it also **UPDATE**s
existing orders through a realistic status lifecycle
(`PENDING → PAID → SHIPPED → DELIVERED`, with ~10% getting `CANCELLED` before
shipping), so the Debezium CDC stream carries genuine update events — not just
inserts.

On startup it creates the `public.orders` table if it doesn't exist (same DDL
as [`../cdc/sql/init.sql`](../cdc/sql/init.sql)).

## Configuration

All configuration is via environment variables. **For Aiven Apps these are set
in the Aiven Apps setup (env vars / secrets) — nothing is baked into the image
and no secret is committed to git.** For local dev, copy `.env.example` to `.env`
and `source` it.

| Variable | Required | Default | Notes |
|----------|----------|---------|-------|
| `POSTGRES_URI` | yes | — | Aiven PG service URI (Console → Connection info), e.g. `postgres://avnadmin:pass@host:port/defaultdb?sslmode=require`. |
| `ORDERS_PER_MINUTE` | no | `100` | INSERT rate; one new order every `60s / rate`. |
| `UPDATES_PER_MINUTE` | no | `60` | Status-UPDATE rate, applied to a random recent non-terminal order. |
| `PORT` | no | `8080` | Health-server port: `/healthz` (liveness), `/readyz` (ready once connected). |

## Run locally

```bash
cp .env.example .env      # fill in your Postgres URI
source .env
go run .
```

You'll see periodic progress logs. Stop with Ctrl-C (SIGINT) — the worker
shuts down gracefully and reports how many orders it inserted/updated. It also
handles SIGTERM, which is how Aiven Apps stops a worker.

## Build & run the container

Via Compose (reads `.env`):

```bash
docker compose up --build
```

Or build the image directly:

```bash
docker build -t live-orders .
# or: podman build -t live-orders .
```

The image is a static binary on a distroless base. It serves a small health
endpoint on `PORT` (default `8080`) — `/healthz` (liveness) and `/readyz` (ready
once connected to Postgres) — so Aiven Apps has a port to probe; otherwise it's
a headless writer. Deploy it to Aiven Apps as a **long-running worker** (via
the `compose.yaml` recipe) and supply the environment variables above in the
Aiven Apps configuration.

## Tests

Unit tests (no database needed):

```bash
go test ./...
```

Covers order generation invariants, the rate→interval math, and the status
transition rules.

## Notes

- **Connection:** TLS via `sslmode=require` in the service URI — no CA file
  needed for Aiven PG's default configuration.
- **Column naming is snake_case** (`order_id`, `customer_id`, ...) — Debezium
  propagates the Postgres column names as-is into Kafka and the auto-created
  Iceberg table.
- **`amount` is `double precision`, not `numeric`** — deliberate, so Debezium's
  JSON output stays a plain number (Debezium encodes `numeric` as base64 bytes
  by default).
- **Freshness:** orders reach Iceberg through Debezium → Kafka → the Iceberg
  sink, which commits on an interval, so downstream queries see
  *near*-real-time data.
