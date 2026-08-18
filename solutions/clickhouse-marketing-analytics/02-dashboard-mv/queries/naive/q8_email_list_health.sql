-- Q8 Email list health — Tinybird's SQL, verbatim.
-- Source: https://www.tinybird.co/blog/clickhouse-marketing-dashboards
-- Only adaptation: table name marketing_events -> campaign_events.
SELECT
    toStartOfWeek(event_time)                   AS week,
    source,
    countIf(event_type = 'email_send')          AS sends,
    countIf(event_type = 'unsubscribe')         AS unsubscribes,
    countIf(event_type = 'bounce')              AS bounces,
    round(
        countIf(event_type = 'unsubscribe') /
        nullIf(countIf(event_type = 'email_send'), 0) * 100, 3
    )                                           AS unsub_rate_pct,
    round(
        countIf(event_type = 'bounce') /
        nullIf(countIf(event_type = 'email_send'), 0) * 100, 3
    )                                           AS bounce_rate_pct
FROM campaign_events
WHERE channel = 'email'
  AND event_time >= today() - 90
GROUP BY week, source
ORDER BY week DESC, unsub_rate_pct DESC;
