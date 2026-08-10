-- Q1 Campaign performance: daily users, purchases, revenue, AOV per channel,
-- last 30 days of data. Reads the pre-aggregated rollup (AggregatingMergeTree),
-- NOT the raw table -- this is the "dashboards stay fast while ingest runs" demo point.
-- NB: output aliases must not shadow the rollup's column names (users, purchases,
-- revenue), or the -Merge calls resolve to the alias and fail.
SELECT
    day,
    channel,
    uniqMerge(users)                                        AS uniq_users,
    uniqMerge(sessions)                                     AS uniq_sessions,
    sum(events)                                             AS total_events,
    sum(purchases)                                          AS total_purchases,
    round(sumMerge(revenue))                                AS revenue_idr,
    round(total_purchases / uniq_users, 4)                  AS purchase_rate,
    round(revenue_idr / nullIf(total_purchases, 0))         AS aov_idr
FROM daily_campaign_rollup
WHERE day >= (SELECT max(day) FROM daily_campaign_rollup) - 29
GROUP BY day, channel
ORDER BY day, channel;
