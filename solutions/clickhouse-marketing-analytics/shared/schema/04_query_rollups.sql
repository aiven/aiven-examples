-- Query optimization: per-chart rollups extending the Q1 pattern
-- (AggregatingMergeTree target + MV) to Q2 / Q4 / Q6 / Q8. Each rollup is
-- keyed to its query's GROUP BY and filtered to its query's WHERE, with
-- event_type in the sort key so one uniq/sum state column serves every
-- funnel stage via the -MergeIf combinator.
--
-- Data facts these keys rely on (verified on the 340.7M-row backfill):
--   * ad_group is never NULL where channel='paid_search' AND keyword IS NOT NULL
--   * campaign_id -> channel is 1:1
--
-- All are tiny: low-cardinality keys x event_type x day (tens of thousands
-- of rows vs 340M raw). Backfill inserts for pre-existing data are at the
-- bottom of this file -- MVs only see blocks inserted after creation.

-- ---------------------------------------------------------------------------
-- Q2: keyword-level paid search
--
-- Shape chosen by measurement (local 26.3, 340.7M rows). 11,600 keyword x
-- ad_group combos make high-cardinality uniq states THE cost of this rollup;
-- variants tested:
--   exact uniq + day key:        1.49M rows, 453 MB, query 1.4s
--   exact uniq, no day:            58k rows, 292 MB, query 2.1s (all-time states are huge)
--   uniqCombined(14), day:       1.49M rows, 573 MB, query 0.85s
--   uniqCombined(14), no day:      58k rows, 120 MB, query 0.80s
--   uniqCombined(12), no day:      58k rows,  56 MB, query 0.41s  <-- this one
-- No day key: the Q2 chart is all-time (blog verbatim); daily grain belongs
-- to daily_campaign_rollup. uniqCombined(12) is ~1% error on the two uniq
-- columns only -- purchases/revenue/ordering stay exact.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS keyword_rollup
(
    keyword    LowCardinality(String),
    ad_group   LowCardinality(String),
    event_type LowCardinality(String),
    sessions   AggregateFunction(uniqCombined(12), String),
    users      AggregateFunction(uniqCombined(12), String),
    events     SimpleAggregateFunction(sum, UInt64),
    revenue    AggregateFunction(sum, Nullable(Float64))
)
ENGINE = AggregatingMergeTree
ORDER BY (keyword, ad_group, event_type);

CREATE MATERIALIZED VIEW IF NOT EXISTS keyword_rollup_mv
TO keyword_rollup
AS
SELECT
    assumeNotNull(keyword)             AS keyword,
    assumeNotNull(ad_group)            AS ad_group,
    event_type,
    uniqCombinedState(12)(session_id)  AS sessions,
    uniqCombinedState(12)(user_id)     AS users,
    count()                            AS events,
    sumState(conversion_value)         AS revenue
FROM campaign_events
WHERE channel = 'paid_search' AND keyword IS NOT NULL
GROUP BY keyword, ad_group, event_type;

-- ---------------------------------------------------------------------------
-- Q4: conversion funnel per campaign
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS funnel_rollup
(
    campaign_id LowCardinality(String),
    channel     LowCardinality(String),
    event_type  LowCardinality(String),
    day         Date,
    users       AggregateFunction(uniqCombined(14), String)
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
    toDate(event_time)           AS day,
    uniqCombinedState(14)(user_id) AS users
FROM campaign_events
WHERE campaign_id != ''
GROUP BY campaign_id, channel, event_type, day;

-- ---------------------------------------------------------------------------
-- Q6: landing page / SEO conversion by traffic source
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS landing_page_rollup
(
    landing_page LowCardinality(String),
    channel      LowCardinality(String),
    event_type   LowCardinality(String),
    day          Date,
    sessions     AggregateFunction(uniqCombined(14), String),
    users        AggregateFunction(uniqCombined(14), String),
    revenue      AggregateFunction(sum, Nullable(Float64))
)
ENGINE = AggregatingMergeTree
PARTITION BY toYYYYMM(day)
ORDER BY (landing_page, channel, event_type, day);

CREATE MATERIALIZED VIEW IF NOT EXISTS landing_page_rollup_mv
TO landing_page_rollup
AS
SELECT
    assumeNotNull(landing_page)       AS landing_page,
    channel,
    event_type,
    toDate(event_time)                AS day,
    uniqCombinedState(14)(session_id) AS sessions,
    uniqCombinedState(14)(user_id)    AS users,
    sumState(conversion_value)        AS revenue
FROM campaign_events
WHERE landing_page IS NOT NULL
GROUP BY landing_page, channel, event_type, day;

-- ---------------------------------------------------------------------------
-- Q8: email list health per campaign (pure counters)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS email_health_rollup
(
    campaign_id LowCardinality(String),
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
    event_type,
    toDate(event_time) AS day,
    count()            AS events
FROM campaign_events
WHERE channel = 'email' AND campaign_id != ''
  AND event_type IN ('email_send', 'unsubscribe', 'bounce')
GROUP BY campaign_id, event_type, day;

-- ===========================================================================
-- One-time backfill (run once, AFTER creating the tables/MVs above, for data
-- inserted before the MVs existed). Each is the MV's SELECT re-run over the
-- full raw table. Re-running duplicates states -- TRUNCATE the rollup first
-- if you must redo one.
-- ===========================================================================
-- INSERT INTO keyword_rollup
-- SELECT assumeNotNull(keyword), assumeNotNull(ad_group), event_type,
--        uniqCombinedState(12)(session_id), uniqCombinedState(12)(user_id),
--        count(), sumState(conversion_value)
-- FROM campaign_events
-- WHERE channel = 'paid_search' AND keyword IS NOT NULL
-- GROUP BY 1, 2, 3;

-- INSERT INTO funnel_rollup
-- SELECT campaign_id, channel, event_type, toDate(event_time),
--        uniqCombinedState(14)(user_id)
-- FROM campaign_events
-- WHERE campaign_id != ''
-- GROUP BY 1, 2, 3, 4;

-- INSERT INTO landing_page_rollup
-- SELECT assumeNotNull(landing_page), channel, event_type, toDate(event_time),
--        uniqCombinedState(14)(session_id), uniqCombinedState(14)(user_id),
--        sumState(conversion_value)
-- FROM campaign_events
-- WHERE landing_page IS NOT NULL
-- GROUP BY 1, 2, 3, 4;

-- INSERT INTO email_health_rollup
-- SELECT campaign_id, event_type, toDate(event_time), count()
-- FROM campaign_events
-- WHERE channel = 'email' AND campaign_id != ''
--   AND event_type IN ('email_send', 'unsubscribe', 'bounce')
-- GROUP BY 1, 2, 3;
