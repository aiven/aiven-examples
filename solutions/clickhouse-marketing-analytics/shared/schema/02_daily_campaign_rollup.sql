-- Pre-aggregation layer (the blog's MV pattern): AggregatingMergeTree target +
-- materialized view. Dashboards read this in milliseconds while raw ingestion
-- runs at full speed; the MV executes once per insert *block*, which is a second
-- reason batched inserts beat row-by-row.
--
-- Query pattern:
--   SELECT day, channel, campaign_id,
--          uniqMerge(users)  AS users,
--          uniqMerge(sessions) AS sessions,
--          sum(events)     AS events,
--          sum(purchases)  AS purchases,
--          sumMerge(revenue) AS revenue
--   FROM daily_campaign_rollup
--   GROUP BY day, channel, campaign_id;

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
    countIf(event_type = 'purchase') AS purchases,
    sumState(conversion_value)       AS revenue
FROM campaign_events
GROUP BY day, channel, campaign_id, country, device_type;
