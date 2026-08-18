-- Q1 rollup — the article's core demo object: AggregatingMergeTree target +
-- materialized view. The MV is an INSERT TRIGGER: it runs its SELECT on each
-- inserted block of campaign_events and appends partial aggregate *states* to
-- this table. Nothing is refreshed; nothing recomputed on read. Dashboards
-- read a few thousand pre-aggregated rows while ingest runs at full speed.
--
-- Store states, not finals: uniqState/sumState here, uniqMerge/sumMerge in
-- the reading query (queries/optimized/q1_campaign_performance.sql). States
-- are mergeable, so one rollup serves any coarser re-grouping (channel-only,
-- week grain, ...). Plain counters use SimpleAggregateFunction(sum) — the
-- sanctioned exception, since partial sums merge by summing.
--
-- uniq (not uniqExact, not uniqCombined) is deliberate: it is the estimator
-- the naive Tinybird queries use, and merged uniq states return the same
-- estimate as a direct uniq() over the raw rows — so the rollup-read answers
-- match the naive answers exactly, sketch for sketch.
--
-- Backfill note: the MV only fires on blocks inserted AFTER it exists. For
-- pre-existing data run the one-time INSERT at the bottom of this file.

CREATE TABLE IF NOT EXISTS daily_campaign_rollup
(
    day         Date,
    channel     LowCardinality(String),
    campaign_id LowCardinality(String),
    country     LowCardinality(String),
    device_type LowCardinality(String),
    users       AggregateFunction(uniq, String),
    sessions    AggregateFunction(uniq, String),
    events      SimpleAggregateFunction(sum, UInt64),
    leads       SimpleAggregateFunction(sum, UInt64),
    purchases   SimpleAggregateFunction(sum, UInt64),
    revenue     AggregateFunction(sum, Nullable(Float64))
)
ENGINE = AggregatingMergeTree
PARTITION BY toYYYYMM(day)
ORDER BY (channel, campaign_id, day, country, device_type);

CREATE MATERIALIZED VIEW IF NOT EXISTS daily_campaign_rollup_mv
TO daily_campaign_rollup
AS
SELECT
    toDate(event_time)               AS day,
    channel,
    campaign_id,
    country,
    device_type,
    uniqState(user_id)               AS users,
    uniqState(session_id)            AS sessions,
    count()                          AS events,
    countIf(event_type = 'lead')     AS leads,
    countIf(event_type = 'purchase') AS purchases,
    sumState(conversion_value)       AS revenue
FROM campaign_events
GROUP BY day, channel, campaign_id, country, device_type;

-- ===========================================================================
-- One-time backfill for rows inserted before the MV existed. Re-running
-- duplicates states — TRUNCATE daily_campaign_rollup first if you must redo.
-- ===========================================================================
-- INSERT INTO daily_campaign_rollup
-- SELECT toDate(event_time), channel, campaign_id, country, device_type,
--        uniqState(user_id), uniqState(session_id),
--        count(), countIf(event_type = 'lead'), countIf(event_type = 'purchase'),
--        sumState(conversion_value)
-- FROM campaign_events
-- GROUP BY 1, 2, 3, 4, 5;
