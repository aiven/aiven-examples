-- One-time Postgres setup for the live-orders CDC pipeline.
-- Run as avnadmin against the Aiven for PostgreSQL service, e.g.:
--
--   psql "$POSTGRES_URI" -f init.sql
--
-- live-orders also runs the CREATE TABLE itself on startup (IF NOT EXISTS),
-- so the table half is optional — but the publication must exist BEFORE the
-- Debezium connector starts (the connector config uses
-- publication.autocreate.mode=disabled and expects this exact name).

-- The orders table live-orders writes into.
--
-- Deliberate choices for clean Debezium JSON output:
--   * amount is double precision, not numeric  -> plain JSON number
--     (Debezium encodes numeric as base64 bytes by default)
--   * order_id is an identity PK               -> stable upsert key for the
--     Iceberg sink, IDs survive producer restarts
--   * snake_case column names propagate as-is to Kafka and the auto-created
--     Iceberg table
CREATE TABLE IF NOT EXISTS public.orders (
    order_id    integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id integer          NOT NULL,
    product     text             NOT NULL,
    quantity    integer          NOT NULL,
    amount      double precision NOT NULL,
    status      text             NOT NULL,
    order_date  timestamptz      NOT NULL DEFAULT now(),
    updated_at  timestamptz      NOT NULL DEFAULT now()
);

-- Publication for logical replication (pgoutput). Scoped to just this table —
-- FOR ALL TABLES would require superuser, which Aiven PG doesn't hand out
-- (that's what the aiven_extras extension is for, not needed here since
-- avnadmin owns public.orders).
CREATE PUBLICATION live_orders_publication FOR TABLE public.orders;

-- Default REPLICA IDENTITY (primary key) is sufficient: we only stream INSERTs
-- and UPDATEs, and the Iceberg sink upserts on order_id. No change needed.
