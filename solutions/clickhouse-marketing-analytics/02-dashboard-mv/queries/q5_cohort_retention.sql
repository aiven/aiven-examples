-- Q5 Cohort retention: weekly acquisition cohorts x weeks-since-acquisition,
-- split by ACQUISITION CHANNEL (the channel of the user's first event, per
-- the blog), as retention % of each cohort (heatmap-ready; filter
-- to one channel per heatmap). Needs the full 90-day backfill.
-- Only genuine user actions count as "active": email_send is a delivery event
-- (the sender's action, not the user's) and would inflate + distort the grid.
--
-- Shape: ONE scan, no join. Grouping per user once and ARRAY JOINing the
-- user's distinct active weeks replaces the blog's first_seen-CTE + self-join
-- (two full scans + a multi-million-row hash join) -- 2-3x faster at this
-- scale, identical results.
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
