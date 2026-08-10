-- campaign_events: the customer's exact DDL (the tinybird "marketing_events" schema,
-- same columns / engine / partitioning / sort key), with their one deviation kept:
-- campaign_id is LowCardinality(String) DEFAULT '' instead of the blog's
-- LowCardinality(Nullable(String)) — non-Nullable is better (and keeps the sort
-- key free of Nullable columns).
--
-- Aiven note: ENGINE = MergeTree is auto-remapped to ReplicatedMergeTree on Aiven;
-- the DDL runs unchanged but SHOW CREATE TABLE will differ from a local run.

CREATE TABLE IF NOT EXISTS campaign_events
(
    event_time       DateTime64(3),
    event_type       LowCardinality(String),
    user_id          String,
    session_id       String,
    campaign_id      LowCardinality(String) DEFAULT '',
    channel          LowCardinality(String),
    source           LowCardinality(Nullable(String)),
    medium           LowCardinality(Nullable(String)),
    ad_group         LowCardinality(Nullable(String)),
    keyword          LowCardinality(Nullable(String)),
    landing_page     LowCardinality(Nullable(String)),
    conversion_value Nullable(Float64),
    currency         LowCardinality(Nullable(String)),
    country          LowCardinality(String),
    device_type      LowCardinality(String),
    properties       String
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(event_time)
ORDER BY (channel, campaign_id, event_time, user_id);
