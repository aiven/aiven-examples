# CDC pipeline: Postgres → Debezium → Kafka → Iceberg

Wiring for the end-to-end CDC leg of the demo:

```
live-orders ─► Aiven PostgreSQL ─► Debezium PG source ─► Aiven Kafka ─► Iceberg sink ─► Iceberg / S3
              (public.orders)     (Aiven Kafka Connect)  (topic:        (upsert mode)   (ecommerce.live_orders,
                                                          live_orders.                   Snowflake Open Catalog)
                                                          public.orders)
```

Both connectors run on the **same Aiven Kafka Connect service** you already
have from `aiven-iceberg-tutorial`. This folder holds the two connector
configs (with placeholders) and the Postgres init SQL.

| File | What it is |
|------|------------|
| [`sql/init.sql`](sql/init.sql) | `orders` table DDL + the logical-replication publication |
| [`debezium-postgres-source.json`](debezium-postgres-source.json) | Debezium CDC source: Postgres → Kafka |
| [`iceberg-sink-live-orders.json`](iceberg-sink-live-orders.json) | Iceberg sink for the CDC topic (upsert mode) |

## Setup, in order

### 1. Aiven for PostgreSQL

Create the service (same project; any plan ≥ `startup-4` works for the demo):

```bash
avn service create live-orders-pg --service-type pg --plan startup-4 --cloud aws-eu-west-1
```

Aiven PG ships with `wal_level=logical` already — no config change needed for
pgoutput. Then run the init SQL as `avnadmin`:

```bash
psql "$(avn service get live-orders-pg --format '{service_uri}')" -f sql/init.sql
```

This creates `public.orders` and — the part the connector can't do itself —
the publication `live_orders_publication`. (live-orders auto-creates the table
too, but the **publication must exist before the Debezium connector starts**:
the config pins `publication.autocreate.mode=disabled` so the connector never
tries to create it with broader scope than intended.)

Point `live-orders` at the service (`POSTGRES_URI`) and start it so there's
data flowing.

### 2. Debezium source connector

Fill the `database.*` placeholders in
[`debezium-postgres-source.json`](debezium-postgres-source.json) from the PG
service's Connection information, then create the connector on the existing
Kafka Connect service (Console → Connectors → Create → *Debezium — PostgreSQL*,
paste the JSON; or via API):

```bash
avn service connector create <your-kafka>-connect @debezium-postgres-source.json
```

What the non-obvious settings do:

- **`plugin.name=pgoutput`** — the built-in logical decoding plugin; no
  wal2json/decoderbufs install needed on Aiven PG.
- **`publication.autocreate.mode=disabled`** + **`publication.name`** — use the
  publication from `init.sql` (scoped to just `public.orders`).
- **`slot.name=live_orders_cdc`** — the replication slot Debezium creates.
  ⚠️ If you later delete the connector permanently, drop the slot
  (`SELECT pg_drop_replication_slot('live_orders_cdc');`) or WAL retention
  will grow unbounded.
- **`topic.prefix=live_orders`** → records land on topic
  **`live_orders.public.orders`** (`<prefix>.<schema>.<table>`). On older
  Debezium 1.x this property is called `database.server.name` instead — check
  which Debezium version your Connect service runs.
- **`transforms=unwrap`** (`ExtractNewRecordState`) — flattens the Debezium
  CDC envelope (`before`/`after`/`op`/`source`) into a plain row, so the
  Iceberg sink sees the same flat JSON shape it always has. Both INSERTs and
  UPDATEs come out as the full new row.
- **`decimal.handling.mode=double`** — belt-and-braces: `amount` is already
  `double precision` in the table, but this keeps any future `numeric` column
  from arriving as base64 bytes.
- **`tombstones.on.delete=false`** — we don't stream deletes; keeps the topic
  clean if a manual DELETE ever happens.
- **`heartbeat.interval.ms=30000`** — keeps the replication slot advancing.
- **`topic.creation.*`** — lets Connect create `live_orders.public.orders`
  (3 partitions, RF 2) itself, so you don't have to pre-create the topic.
- **Converters: JSON with `schemas.enable=false`** — matches what the Iceberg
  sink expects (same as the original pipeline). `timestamptz` columns arrive
  as ISO-8601 strings, same as the old producer's `orderDate`.

### 3. Iceberg sink connector (new one, for the CDC topic)

The original `order`-topic sink stays as-is (or retire it — nothing writes to
`order` anymore). Create a **second** sink from
[`iceberg-sink-live-orders.json`](iceberg-sink-live-orders.json) after filling
in the same catalog/S3/Kafka values you used in the tutorial's Terraform:

```bash
avn service connector create <your-kafka>-connect @iceberg-sink-live-orders.json
```

Differences vs. the original sink — these are the adjustments needed so CDC
data lands correctly:

- **`topics=live_orders.public.orders`**, **`iceberg.tables=ecommerce.live_orders`**
  — new topic, new table. Auto-created on first commit; snake_case columns.
- **Upsert mode**: `iceberg.tables.upsert-mode-enabled=true` +
  `iceberg.tables.default-id-columns=order_id`. Because live-orders UPDATEs
  order statuses, the same `order_id` appears multiple times on the topic;
  upsert mode makes the Iceberg table hold one current row per order
  (equality-delete + append) instead of duplicate append-only rows.
- **No `KeyToValue` transform** — the old producer's synthetic `keyId` key is
  gone; Debezium's key is the real primary key and `order_id` is already in
  the value.
- **Own control topic + group id** (`control-iceberg-live-orders` /
  `cg-control-iceberg-live-orders`) so the two sinks on the shared Connect
  service never cross-commit. Pre-create the control topic (3 partitions,
  RF 2) or enable topic auto-creation on the Kafka service.
- **Commit interval 5000 ms** — don't go low: sub-second intervals bloat the
  control topic and replay from earliest on restart, blocking real commits.

### 4. Verify end to end

```bash
# 1. Rows changing in Postgres
psql "$POSTGRES_URI" -c "SELECT status, count(*) FROM orders GROUP BY 1;"

# 2. CDC events on the topic (kcat, SASL creds from the Console)
kcat -b <kafka-host>:<sasl-port> -X security.protocol=SASL_SSL \
     -X sasl.mechanisms=SCRAM-SHA-512 -X sasl.username=avnadmin \
     -X sasl.password=<pw> -t live_orders.public.orders -C -o -3 -e

# 3. Table visible in Snowflake Open Catalog (ecommerce.live_orders), then:
#    ask the query-agent "how many orders are currently SHIPPED?" — it reads
#    the table through Trino.
```

## Operational gotchas (learned the hard way on the original sink)

- **Sink consumer may start at latest** despite
  `consumer.override.auto.offset.reset=earliest` — create the sink *before*
  (or while) data flows, or expect pre-existing records to be skipped. With
  `snapshot.mode=initial` on Debezium, recreating the source connector with a
  fresh slot re-snapshots the whole table, which is an easy way to backfill.
- **S3 region**: bucket must be co-located with the Open Catalog account
  region (us-west-2) — a mismatch surfaces as an HTTP 301 wrapped in a
  `RESTException` from `createTable`.
- **IAM**: the sink's static S3 user needs `s3:PutObject` on the bucket, or
  table creation succeeds but data commits 403.
- **Never pause/resume the Iceberg sink** — it kills the REST catalog HTTP
  pool JVM-wide (`Connection pool shut down`); only a full power-cycle of the
  Kafka Connect service recovers it.
- **`tasks.max=1`** on both connectors — a single PG table / low-throughput
  demo gains nothing from more tasks, and the Iceberg coordinator is calmer.
