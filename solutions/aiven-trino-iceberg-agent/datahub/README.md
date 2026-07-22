# Aiven for DataHub: lineage for the CDC pipeline

Goal: see the whole journey in one graph —

```
live-orders ─► postgres:public.orders ─► [Debezium connector] ─► kafka:live_orders.public.orders ─► [Iceberg sink] ─► iceberg:ecommerce.live_orders
```

The managed service (`datahub-demo`, `aws-eu-west-1` — DataHub has no
us-west-2 plans; a metadata service reads the us-west-2 services cross-region
just fine) has no Aiven-side ingestion integrations: recipes are configured
**inside the DataHub UI**. This folder holds the four recipes.

| Recipe | Ingests | Lineage it contributes |
|--------|---------|------------------------|
| [`postgres.yml`](postgres.yml) | `public.orders` schema | the source node |
| [`kafka.yml`](kafka.yml) | the CDC topic | the stream node |
| [`kafka-connect.yml`](kafka-connect.yml) | both connectors | **postgres → topic** (DataHub understands Debezium natively) |
| [`iceberg.yml`](iceberg.yml) | `ecommerce.live_orders` schema | the lake node |

## Setup

1. **Open the DataHub UI** — Aiven Console → `datahub-demo` → service URI
   (`https://<uuid>-9002.eur-1.aiven.app`).
2. **Create secrets** (UI → Ingestion → Secrets): `PG_PASSWORD`,
   `KAFKA_PASSWORD`, `CONNECT_PASSWORD` (each service's avnadmin password from
   its Connection info page), and `OC_DATAHUB_CREDENTIAL` (see step 3).
3. **Read-only Open Catalog connection** (deliberately not reusing the
   pipeline's read-write credential): Snowflake Open Catalog UI → Connections
   → + Connection (e.g. `datahub-conn`, new principal role
   `datahub-principal`) → create a catalog role with read-only privileges
   (namespace/table list + read) → grant to `datahub-principal`. Put
   `<client-id>:<client-secret>` into the `OC_DATAHUB_CREDENTIAL` secret and
   the principal role name into `iceberg.yml`.
4. **Create the four ingestion sources** (UI → Ingestion → Create new source →
   paste YAML), run them, and check each finishes `Succeeded`.
5. **Look at the graph**: search `live_orders` → open the Kafka topic → Lineage
   tab. You should see Postgres on the left (via the Debezium connector) and —
   once the last edge is closed (below) — Iceberg on the right.

## Closing the last lineage edge (topic → Iceberg table)

DataHub's `kafka-connect` source recognizes Debezium *sources* natively, but
the Apache Iceberg *sink* is not among its known sink classes, so the
`kafka:live_orders.public.orders → iceberg:ecommerce.live_orders` edge is not
emitted automatically. Two options:

- **Emitter script (repeatable — what this repo uses):**
  [`emit-lineage.py`](emit-lineage.py). Create a personal access token in the
  DataHub UI (Settings → Access Tokens), then:
  ```bash
  cd datahub && python3 -m venv venv && ./venv/bin/pip install acryl-datahub
  export DATAHUB_GMS_URL="https://<datahub-frontend-host>/api/gms"
  export DATAHUB_TOKEN="<token>"
  ./venv/bin/python emit-lineage.py
  ```
- **Manual edge (UI alternative):** the Kafka topic → Lineage tab →
  *Edit lineage* → add downstream → pick `ecommerce.live_orders`. Also
  survives re-ingestion.

## Notes

- The Kafka recipe uses the **Let's Encrypt SASL listener** (port `10599`), so
  no CA bundle upload is needed.
- The Connect recipe needs the Connect service's **public** endpoint
  (`public-…-connect-….aivencloud.com:443`) — the internal one is not
  reachable from DataHub's ingestion executor.
- None of the recipes set a `platform_instance` — and `kafka-connect.yml`
  deliberately has no `platform_instance_map`. Instance naming must agree
  across ALL recipes (all unset, or all matching), or the connector's lineage
  edges point at instance-prefixed nodes that don't exist and the graph shows
  disconnected duplicates.
- Schedule: each source can run on a cron in the UI; hourly is plenty — the
  schema barely changes, only freshness metadata does.
