-- Q4 Conversion funnel — Tinybird's SQL, verbatim.
-- Source: https://www.tinybird.co/blog/clickhouse-marketing-dashboards
-- Only adaptation: table name marketing_events -> campaign_events.
SELECT
    campaign_id,
    channel,
    uniq(user_id)                                       AS visitors,
    uniqIf(user_id, event_type = 'lead')                AS leads,
    uniqIf(user_id, event_type = 'trial_start')         AS trial_starts,
    uniqIf(user_id, event_type = 'purchase')            AS purchasers,
    round(
        uniqIf(user_id, event_type = 'lead') /
        uniq(user_id) * 100, 1
    )                                                   AS visitor_to_lead_pct,
    round(
        uniqIf(user_id, event_type = 'purchase') /
        nullIf(uniqIf(user_id, event_type = 'lead'), 0) * 100, 1
    )                                                   AS lead_to_purchase_pct
FROM campaign_events
WHERE event_time >= today() - 30
GROUP BY campaign_id, channel
HAVING visitors >= 100
ORDER BY visitors DESC;
