-- Q7 — no optimization needed; identical to queries/naive/q7_email_hourly.sql.
-- The 7-day window partition-prunes the scan to a sliver of the table and the
-- naive query already answers in fractions of a second. Kept here so every
-- panel reads from queries/optimized/ — the "fix" is knowing when not to.
SELECT
    campaign_id,
    toStartOfHour(event_time)                   AS hour,
    countIf(event_type = 'email_send')          AS sends,
    countIf(event_type = 'email_open')          AS opens,
    countIf(event_type = 'email_click')         AS clicks,
    countIf(event_type = 'purchase')            AS conversions,
    round(
        countIf(event_type = 'email_open') /
        nullIf(countIf(event_type = 'email_send'), 0) * 100, 2
    )                                           AS open_rate_pct,
    round(
        countIf(event_type = 'email_click') /
        nullIf(countIf(event_type = 'email_open'), 0) * 100, 2
    )                                           AS click_to_open_pct,
    round(sum(conversion_value), 2)             AS revenue
FROM campaign_events
WHERE channel = 'email'
  AND event_time >= today() - 7
GROUP BY campaign_id, hour
ORDER BY hour DESC, sends DESC;
