-- Q2 Keyword-level paid search — Tinybird's SQL, verbatim.
-- Source: https://www.tinybird.co/blog/clickhouse-marketing-dashboards
-- Only adaptation: table name marketing_events -> campaign_events.
SELECT
    keyword,
    ad_group,
    uniq(session_id)                        AS sessions,
    countIf(event_type = 'purchase')        AS conversions,
    round(sum(conversion_value), 2)         AS revenue,
    round(
        sum(conversion_value) /
        uniq(session_id), 2
    )                                       AS revenue_per_session
FROM campaign_events
WHERE channel = 'paid_search'
  AND keyword IS NOT NULL
  AND event_time >= today() - 14
GROUP BY keyword, ad_group
HAVING sessions >= 50
ORDER BY revenue_per_session DESC
LIMIT 100;
