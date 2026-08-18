-- Q6 Landing page / SEO — Tinybird's SQL, verbatim.
-- Source: https://www.tinybird.co/blog/clickhouse-marketing-dashboards
-- Only adaptation: table name marketing_events -> campaign_events.
SELECT
    landing_page,
    channel,
    toStartOfWeek(event_time)           AS week,
    uniq(session_id)                    AS sessions,
    uniq(user_id)                       AS unique_users,
    countIf(event_type = 'lead')        AS leads,
    countIf(event_type = 'purchase')    AS purchases,
    round(
        countIf(event_type = 'lead') /
        uniq(session_id) * 100, 2
    )                                   AS landing_to_lead_pct,
    round(sum(conversion_value), 2)     AS revenue
FROM campaign_events
WHERE channel IN ('organic', 'paid_search', 'social')
  AND landing_page IS NOT NULL
  AND event_time >= today() - 30
GROUP BY landing_page, channel, week
HAVING sessions >= 100
ORDER BY week DESC, sessions DESC;
