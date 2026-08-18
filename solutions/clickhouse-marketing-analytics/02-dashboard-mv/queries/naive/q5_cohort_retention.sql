-- Q5 Cohort retention — Tinybird's self-join formulation, minimally corrected.
-- Source: https://www.tinybird.co/blog/clickhouse-marketing-dashboards
--
-- The article's printed query does not execute in ClickHouse as published:
--   (1) its cohorts subquery puts an aggregate (toStartOfWeek(min(event_time)))
--       in its own GROUP BY key, which is invalid SQL;
--   (2) its activity subquery computes min(event_time) per (user, channel,
--       week), so "first_event" is the first event of each WEEK and
--       weeks_since_acquisition collapses to 0 for every row.
-- This file keeps the article's structure and intent — first-seen per user x
-- channel, self-joined against weekly activity, cohort_size from a third
-- aggregation — with only those two defects fixed. It is still the honest
-- baseline: multiple full scans of the raw table plus multi-million-row joins.
WITH firsts AS
(
    SELECT
        user_id,
        channel,
        min(event_time)                     AS first_event
    FROM campaign_events
    GROUP BY user_id, channel
),
activity AS
(
    SELECT
        user_id,
        channel,
        toStartOfWeek(event_time)           AS activity_week
    FROM campaign_events
    WHERE event_time >= today() - 90
    GROUP BY user_id, channel, toStartOfWeek(event_time)
),
joined AS
(
    SELECT
        a.user_id                           AS user_id,
        a.channel                           AS channel,
        toStartOfWeek(f.first_event)        AS acquisition_week,
        a.activity_week                     AS activity_week
    FROM activity AS a
    INNER JOIN firsts AS f USING (user_id, channel)
)
SELECT
    acquisition_week,
    channel                                 AS acquisition_channel,
    dateDiff('week', acquisition_week, activity_week) AS weeks_since_acquisition,
    uniq(user_id)                           AS retained_users,
    cohort_size,
    round(uniq(user_id) / cohort_size * 100, 1) AS retention_pct
FROM joined
INNER JOIN (
    SELECT
        toStartOfWeek(first_event)          AS acquisition_week,
        channel,
        uniq(user_id)                       AS cohort_size
    FROM firsts
    GROUP BY acquisition_week, channel
) AS cohorts USING (acquisition_week, channel)
WHERE weeks_since_acquisition BETWEEN 0 AND 8
GROUP BY acquisition_week, acquisition_channel, weeks_since_acquisition, cohort_size
ORDER BY acquisition_week DESC, weeks_since_acquisition;
