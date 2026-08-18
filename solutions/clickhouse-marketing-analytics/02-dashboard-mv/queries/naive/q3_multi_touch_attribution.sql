-- Q3 Multi-touch attribution — Tinybird's SQL, verbatim (the window-function
-- formulation). Source: https://www.tinybird.co/blog/clickhouse-marketing-dashboards
-- Only adaptation: table name marketing_events -> campaign_events.
-- This is the CPU-bound baseline: the cost is the window sorts over each
-- user's event stream, not the scan — see the optimized rewrite for the
-- grouped-arrays formulation that returns the same three models.
WITH user_journeys AS (
    SELECT
        user_id,
        channel,
        campaign_id,
        event_time,
        row_number() OVER (
            PARTITION BY user_id
            ORDER BY event_time
        )                                       AS touch_position,
        count() OVER (
            PARTITION BY user_id
        )                                       AS total_touches,
        max(event_time) OVER (
            PARTITION BY user_id
        )                                       AS conversion_time,
        argMax(conversion_value, event_time) OVER (
            PARTITION BY user_id
        )                                       AS conversion_value
    FROM campaign_events
    WHERE user_id IN (
        SELECT user_id FROM campaign_events
        WHERE event_type = 'purchase'
          AND event_time >= today() - 30
    )
      AND event_time >= today() - 30
)
SELECT
    channel,
    campaign_id,
    round(sum(conversion_value / total_touches), 2)        AS linear_attributed_revenue,
    round(sumIf(conversion_value, touch_position = 1), 2)  AS first_touch_revenue,
    round(sumIf(conversion_value, touch_position = total_touches), 2) AS last_touch_revenue,
    count()                                                AS touch_count
FROM user_journeys
GROUP BY channel, campaign_id
ORDER BY linear_attributed_revenue DESC;
