-- Q7 Email hourly analytics — Tinybird's SQL, verbatim.
-- Source: https://www.tinybird.co/blog/clickhouse-marketing-dashboards
-- Only adaptation: table name marketing_events -> campaign_events.
-- Fast by construction: the 7-day window partition-prunes the scan.
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
