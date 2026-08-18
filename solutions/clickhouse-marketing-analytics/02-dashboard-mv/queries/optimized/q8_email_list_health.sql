-- Q8 optimized — reads email_health_rollup (ddl/04): pure pre-summed counters
-- keyed by (campaign_id, source, event_type, day). Bottleneck of the naive
-- version: I/O — counting three event types across 90 days of raw email rows.
-- Fix: the counts were summed at insert time; this reads a few thousand rows.
--
-- Same output shape as queries/naive/q8_email_list_health.sql. No aggregate
-- states involved (counters only), so no -Merge / alias-shadowing concerns.
SELECT
    toStartOfWeek(day)                          AS week,
    source,
    sumIf(events, event_type = 'email_send')    AS sends,
    sumIf(events, event_type = 'unsubscribe')   AS unsubscribes,
    sumIf(events, event_type = 'bounce')        AS bounces,
    round(unsubscribes / nullIf(sends, 0) * 100, 3) AS unsub_rate_pct,
    round(bounces / nullIf(sends, 0) * 100, 3)      AS bounce_rate_pct
FROM email_health_rollup
WHERE day >= today() - 90
GROUP BY week, source
ORDER BY week DESC, unsub_rate_pct DESC;
