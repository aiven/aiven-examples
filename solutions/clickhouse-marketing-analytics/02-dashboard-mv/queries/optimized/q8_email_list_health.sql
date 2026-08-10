-- Q8 optimized: reads email_health_rollup (ddl/04) -- pure counters keyed by
-- (campaign_id, event_type, day), so the 102.5M-row raw scan becomes a few
-- thousand pre-summed rows. Same output as queries/q8_email_list_health.sql.
SELECT
    campaign_id,
    sumIf(events, event_type = 'email_send')                              AS sends,
    round(sumIf(events, event_type = 'unsubscribe') / nullIf(sends, 0) * 100, 2) AS unsub_pct,
    round(sumIf(events, event_type = 'bounce')      / nullIf(sends, 0) * 100, 2) AS bounce_pct,
    if(unsub_pct > 0.5 OR bounce_pct > 2, 'ALERT', 'ok')                  AS list_health
FROM email_health_rollup
GROUP BY campaign_id
HAVING sends > 0
ORDER BY list_health, sends DESC
LIMIT 40;
