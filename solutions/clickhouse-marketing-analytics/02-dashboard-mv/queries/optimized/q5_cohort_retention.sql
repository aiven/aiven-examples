-- Q5 optimized — query rewrite (+ the user_journey projection, ddl/05).
-- Bottleneck of the naive version: multiple full scans plus multi-million-row
-- hash joins (first-seen x weekly-activity x cohort-size). Fix: ONE scan —
-- group each (user, channel) once, take the acquisition week and the set of
-- active weeks together, count the cohort with a window, ARRAY JOIN the
-- active weeks. The user_journey projection accelerates the per-user GROUP BY
-- with no SQL change.
--
-- Same output shape and semantics as queries/naive/q5_cohort_retention.sql:
-- acquisition is per (user, channel); cohort_size counts ALL users acquired
-- that week on that channel (active in the window or not); activity is
-- limited to the last 90 days.
WITH per_user AS
(
    SELECT
        user_id,
        channel,
        toStartOfWeek(min(event_time))          AS acquisition_week,
        groupUniqArrayIf(toStartOfWeek(event_time),
                         event_time >= today() - 90) AS weeks
    FROM campaign_events
    GROUP BY user_id, channel
),
sized AS
(
    -- cohort_size as a WINDOW uniq over the per-user rows: one row per
    -- (user, channel) exists, so this counts the whole cohort — active in
    -- the window or not — with the naive query's own uniq estimator, and
    -- WITHOUT re-evaluating the per_user CTE (ClickHouse inlines CTEs, so a
    -- second reference would scan the raw table again).
    SELECT
        user_id,
        channel,
        acquisition_week,
        weeks,
        uniq(user_id) OVER (PARTITION BY acquisition_week, channel) AS cohort_size
    FROM per_user
)
SELECT
    acquisition_week,
    channel                                     AS acquisition_channel,
    dateDiff('week', acquisition_week, activity_week) AS weeks_since_acquisition,
    uniq(user_id)                               AS retained_users,
    cohort_size,
    round(uniq(user_id) / cohort_size * 100, 1) AS retention_pct
FROM sized
ARRAY JOIN weeks AS activity_week
WHERE weeks_since_acquisition BETWEEN 0 AND 8
GROUP BY acquisition_week, acquisition_channel, weeks_since_acquisition, cohort_size
ORDER BY acquisition_week DESC, weeks_since_acquisition;
