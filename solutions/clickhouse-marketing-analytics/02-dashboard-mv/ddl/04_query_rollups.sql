-- Per-chart rollups extending the Q1 pattern (AggregatingMergeTree target +
-- MV insert trigger) to Q2 / Q4 / Q6 / Q8. Each rollup is keyed to its naive
-- query's GROUP BY and filtered to its WHERE, with event_type in the sort key
-- so one uniq/sum state column serves every stage via the -MergeIf combinator.
--
-- All uniq columns store uniq states (the same estimator the naive Tinybird
-- queries call), so the rollup-read answers match the naive answers exactly.
-- If a rollup's uniq states ever dominate its cost at scale, the measured
-- fallback ladder is uniqCombined(14) then uniqCombined(12) (~0.5%/~1% error;
-- counts, revenue and ordering stay exact) — see the benchmark history in the
-- repo for the variant matrix that informed this.
--
-- Data facts these keys rely on (validated by the datagen gates):
--   * ad_group is never NULL where channel='paid_search' AND keyword IS NOT NULL
--   * campaign_id -> channel is 1:1
--
-- Backfill inserts for pre-existing data are at the bottom of this file —
-- MVs only see blocks inserted after creation.

-- ---------------------------------------------------------------------------
-- Q2: keyword-level paid search. Day-keyed because the naive query is a
-- 14-day window (today() - 14); the reading query re-aggregates across days
-- by merging states.
--
-- NO event_type in the key: Q2's uniqs are over ALL events, and splitting a
-- uniq state by a dimension the query doesn't group by only multiplies the
-- number of heavy states to merge at read time (measured a 679M-row regression
-- before this was removed). Per-type needs are served by plain counters.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS keyword_rollup
(
    keyword    LowCardinality(String),
    ad_group   LowCardinality(String),
    day        Date,
    sessions   AggregateFunction(uniq, String),
    users      AggregateFunction(uniq, String),
    events     SimpleAggregateFunction(sum, UInt64),
    purchases  SimpleAggregateFunction(sum, UInt64),
    revenue    AggregateFunction(sum, Nullable(Float64))
)
ENGINE = AggregatingMergeTree
PARTITION BY toYYYYMM(day)
ORDER BY (keyword, ad_group, day);

CREATE MATERIALIZED VIEW IF NOT EXISTS keyword_rollup_mv
TO keyword_rollup
AS
SELECT
    assumeNotNull(keyword)             AS keyword,
    assumeNotNull(ad_group)            AS ad_group,
    toDate(event_time)                 AS day,
    uniqState(session_id)              AS sessions,
    uniqState(user_id)                 AS users,
    count()                            AS events,
    countIf(event_type = 'purchase')   AS purchases,
    sumState(conversion_value)         AS revenue
FROM campaign_events
WHERE channel = 'paid_search' AND keyword IS NOT NULL
GROUP BY keyword, ad_group, day;

-- ---------------------------------------------------------------------------
-- Q4: conversion funnel per campaign x channel. One uniq state column serves
-- visitors and every funnel stage via uniqMergeIf on the event_type key.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS funnel_rollup
(
    campaign_id LowCardinality(String),
    channel     LowCardinality(String),
    event_type  LowCardinality(String),
    day         Date,
    users       AggregateFunction(uniq, String)
)
ENGINE = AggregatingMergeTree
PARTITION BY toYYYYMM(day)
ORDER BY (campaign_id, channel, event_type, day);

CREATE MATERIALIZED VIEW IF NOT EXISTS funnel_rollup_mv
TO funnel_rollup
AS
SELECT
    campaign_id,
    channel,
    event_type,
    toDate(event_time)   AS day,
    uniqState(user_id)   AS users
FROM campaign_events
GROUP BY campaign_id, channel, event_type, day;

-- ---------------------------------------------------------------------------
-- Q6: landing page / SEO conversion by traffic source. Day grain merges up
-- to the naive query's toStartOfWeek(); the events counter serves the
-- leads/purchases counts.
-- ---------------------------------------------------------------------------
-- NO event_type in the key (same reasoning as keyword_rollup): Q6's uniqs are
-- over all events; leads/purchases are plain counters.
--
-- uniqCombined(14), NOT uniq, and this is measured: at (page, channel, day)
-- grain each cell holds ~30-40k uniques, which keeps exact-uniq states in
-- their large pre-sketch representation — the read merged GIGABYTES of state
-- and lost to the raw scan (8.9s vs 4.0s at 679M rows). uniqCombined(14)
-- caps every state at ~16 KiB for a documented ≤0.5% drift on the two uniq
-- columns ONLY; leads/purchases/revenue stay exact. This is the suite's one
-- bounded approximation, and the equality gate carries a per-query tolerance
-- for it.
CREATE TABLE IF NOT EXISTS landing_page_rollup
(
    landing_page LowCardinality(String),
    channel      LowCardinality(String),
    day          Date,
    sessions     AggregateFunction(uniqCombined(14), String),
    users        AggregateFunction(uniqCombined(14), String),
    leads        SimpleAggregateFunction(sum, UInt64),
    purchases    SimpleAggregateFunction(sum, UInt64),
    revenue      AggregateFunction(sum, Nullable(Float64))
)
ENGINE = AggregatingMergeTree
PARTITION BY toYYYYMM(day)
ORDER BY (landing_page, channel, day);

CREATE MATERIALIZED VIEW IF NOT EXISTS landing_page_rollup_mv
TO landing_page_rollup
AS
SELECT
    assumeNotNull(landing_page)          AS landing_page,
    channel,
    toDate(event_time)                   AS day,
    uniqCombinedState(14)(session_id)    AS sessions,
    uniqCombinedState(14)(user_id)       AS users,
    countIf(event_type = 'lead')         AS leads,
    countIf(event_type = 'purchase')     AS purchases,
    sumState(conversion_value)           AS revenue
FROM campaign_events
WHERE landing_page IS NOT NULL
GROUP BY landing_page, channel, day;

-- ---------------------------------------------------------------------------
-- Q8: email list health (pure counters). source is in the key for the naive
-- (week x source) shape; campaign_id is in the key for the dashboard's
-- per-campaign alert chart — one rollup serves both.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS email_health_rollup
(
    campaign_id LowCardinality(String),
    source      LowCardinality(Nullable(String)),
    event_type  LowCardinality(String),
    day         Date,
    events      SimpleAggregateFunction(sum, UInt64)
)
ENGINE = AggregatingMergeTree
PARTITION BY toYYYYMM(day)
ORDER BY (campaign_id, event_type, day);

CREATE MATERIALIZED VIEW IF NOT EXISTS email_health_rollup_mv
TO email_health_rollup
AS
SELECT
    campaign_id,
    source,
    event_type,
    toDate(event_time) AS day,
    count()            AS events
FROM campaign_events
WHERE channel = 'email'
  AND event_type IN ('email_send', 'unsubscribe', 'bounce')
GROUP BY campaign_id, source, event_type, day;

-- ===========================================================================
-- One-time backfill (run once, AFTER creating the tables/MVs above, for data
-- inserted before the MVs existed). Each is the MV's SELECT re-run over the
-- full raw table. Re-running duplicates states — TRUNCATE the rollup first
-- if you must redo one.
--
-- At 500M+ rows, run each backfill month-by-month (add
-- `AND toYYYYMM(event_time) = 202605` etc.) and/or set
-- `SETTINGS max_bytes_before_external_group_by = 6000000000` — the
-- string-heavy uniq aggregations otherwise exceed typical container memory
-- (measured: an unchunked landing_page backfill needed ~12 GiB at 679M rows).
-- A failed INSERT SELECT can leave partial blocks: TRUNCATE before retrying.
-- ===========================================================================
-- INSERT INTO keyword_rollup
-- SELECT assumeNotNull(keyword), assumeNotNull(ad_group), toDate(event_time),
--        uniqState(session_id), uniqState(user_id),
--        count(), countIf(event_type = 'purchase'), sumState(conversion_value)
-- FROM campaign_events
-- WHERE channel = 'paid_search' AND keyword IS NOT NULL
-- GROUP BY 1, 2, 3;

-- INSERT INTO funnel_rollup
-- SELECT campaign_id, channel, event_type, toDate(event_time),
--        uniqState(user_id)
-- FROM campaign_events
-- GROUP BY 1, 2, 3, 4;

-- INSERT INTO landing_page_rollup
-- SELECT assumeNotNull(landing_page), channel, toDate(event_time),
--        uniqCombinedState(14)(session_id), uniqCombinedState(14)(user_id),
--        countIf(event_type = 'lead'), countIf(event_type = 'purchase'),
--        sumState(conversion_value)
-- FROM campaign_events
-- WHERE landing_page IS NOT NULL
-- GROUP BY 1, 2, 3;

-- INSERT INTO email_health_rollup
-- SELECT campaign_id, source, event_type, toDate(event_time), count()
-- FROM campaign_events
-- WHERE channel = 'email'
--   AND event_type IN ('email_send', 'unsubscribe', 'bounce')
-- GROUP BY 1, 2, 3, 4;
