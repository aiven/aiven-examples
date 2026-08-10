-- Q8 Email list health: unsubscribe and bounce rates per campaign with
-- alert thresholds (unsub > 0.5%, bounce > 2% of sends). Only the 3
-- deliberately-bad segments should say ALERT.
SELECT
    campaign_id,
    countIf(event_type = 'email_send')                            AS sends,
    round(countIf(event_type = 'unsubscribe') / nullIf(sends, 0) * 100, 2) AS unsub_pct,
    round(countIf(event_type = 'bounce')      / nullIf(sends, 0) * 100, 2) AS bounce_pct,
    if(unsub_pct > 0.5 OR bounce_pct > 2, 'ALERT', 'ok')          AS list_health
FROM campaign_events
WHERE channel = 'email' AND campaign_id != ''
GROUP BY campaign_id
HAVING sends > 0
ORDER BY list_health, sends DESC
LIMIT 40;
