-- Q1 Campaign performance — Tinybird's SQL, verbatim.
-- Source: https://www.tinybird.co/blog/clickhouse-marketing-dashboards
-- Only adaptation: table name marketing_events -> campaign_events (our shared
-- schema uses the article's column set). No other changes — this is the
-- honest "what everyone writes first" baseline the optimized track is
-- measured against.
SELECT
    channel,
    campaign_id,
    toStartOfDay(event_time)                            AS day,
    uniq(user_id)                                       AS unique_users,
    count()                                             AS total_events,
    countIf(event_type = 'lead')                        AS leads,
    countIf(event_type = 'purchase')                    AS purchases,
    round(sum(conversion_value), 2)                     AS revenue,
    round(
        countIf(event_type = 'purchase') /
        uniq(user_id) * 100, 2
    )                                                   AS purchase_rate_pct,
    avg(conversion_value)                               AS avg_order_value
FROM campaign_events
WHERE event_time >= today() - 30
GROUP BY channel, campaign_id, day
ORDER BY day DESC, revenue DESC;
