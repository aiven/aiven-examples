-- Q1 optimized — reads daily_campaign_rollup (ddl/01) instead of scanning the
-- raw table. Bottleneck of the naive version: I/O — a 30-day aggregation over
-- the whole event stream, re-run on every dashboard refresh. Fix: the MV paid
-- the aggregation cost at insert time; this reads a few thousand state rows
-- and merges them.
--
-- Same output shape as queries/naive/q1_campaign_performance.sql. Aggregates
-- run in the inner query under internal names, because output aliases must
-- not shadow the rollup's column names (users, leads, revenue, ...) or the
-- -Merge calls resolve to the alias and fail.
SELECT
    channel,
    campaign_id,
    toDateTime(day)                         AS day,  -- naive toStartOfDay() returns DateTime
    u_users                                 AS unique_users,
    n_events                                AS total_events,
    n_leads                                 AS leads,
    n_purch                                 AS purchases,
    round(rev, 2)                           AS revenue,
    round(n_purch / u_users * 100, 2)       AS purchase_rate_pct,
    rev / n_purch                           AS avg_order_value
FROM
(
    SELECT
        channel,
        campaign_id,
        day,
        uniqMerge(users)                    AS u_users,
        sum(events)                         AS n_events,
        sum(leads)                          AS n_leads,
        sum(purchases)                      AS n_purch,
        sumMerge(revenue)                   AS rev
    FROM daily_campaign_rollup
    WHERE day >= today() - 30
    GROUP BY channel, campaign_id, day
)
ORDER BY day DESC, revenue DESC;
