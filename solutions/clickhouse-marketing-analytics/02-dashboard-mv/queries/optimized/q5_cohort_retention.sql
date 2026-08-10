-- Q5 optimized = the baseline SQL unchanged, accelerated by the
-- user_journey projection (ddl/05); ClickHouse selects it automatically.
-- Measured (local 26.3, 340.7M rows, 3 runs each): 3.8-4.0s on the
-- projection vs 6.5-7.8s with it disabled. optimize_aggregation_in_order
-- was tried and rejected (4.0-4.3s: trades parallelism for memory savings
-- the projection scan no longer needs).
SELECT
    acq_channel,
    cohort_week,
    dateDiff('week', cohort_week, week) AS week_n,
    count()                             AS active_users,
    round(active_users / max(active_users) OVER (PARTITION BY acq_channel, cohort_week) * 100, 1) AS retention_pct
FROM
(
    SELECT
        user_id,
        argMin(channel, event_time)               AS acq_channel,
        min(toStartOfWeek(event_time))            AS cohort_week,
        groupUniqArray(toStartOfWeek(event_time)) AS weeks
    FROM campaign_events
    WHERE event_type NOT IN ('email_send', 'bounce', 'unsubscribe')
    GROUP BY user_id
)
ARRAY JOIN weeks AS week
GROUP BY acq_channel, cohort_week, week_n
ORDER BY acq_channel, cohort_week, week_n;
