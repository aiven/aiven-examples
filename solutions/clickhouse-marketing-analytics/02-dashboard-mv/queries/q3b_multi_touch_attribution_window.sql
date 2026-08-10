-- Q3.B Multi-touch attribution, the blog's window-function formulation.
-- Same three models as Q3.A (linear / first-touch / last-touch per channel):
-- each touch finds its next purchase with a window over the user's event
-- stream, journeys are ranked with row_number(), credit is split per model.
-- Kept for fidelity with the article; Q3.A is the recommended production
-- shape (same numbers, fewer sort passes -- see its header).
WITH stream AS
(
    SELECT
        user_id,
        event_time,
        channel,
        event_type,
        conversion_value,
        -- the first purchase at-or-after this event, per user
        minIf(event_time, event_type = 'purchase')
            OVER (PARTITION BY user_id ORDER BY event_time
                  ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING)      AS conv_time,
        argMinIf(conversion_value, event_time, event_type = 'purchase')
            OVER (PARTITION BY user_id ORDER BY event_time
                  ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING)      AS conv_value
    FROM campaign_events
    PREWHERE event_type IN ('page_view', 'click', 'purchase')
    WHERE (campaign_id != '' OR event_type = 'purchase')
      AND user_id IN (SELECT DISTINCT user_id FROM campaign_events WHERE event_type = 'purchase')
),
journeys AS
(
    SELECT
        channel,
        conv_value,
        row_number() OVER (PARTITION BY user_id, conv_time ORDER BY event_time)      AS touch_asc,
        row_number() OVER (PARTITION BY user_id, conv_time ORDER BY event_time DESC) AS touch_desc,
        count()      OVER (PARTITION BY user_id, conv_time)                          AS journey_len
    FROM stream
    WHERE event_type != 'purchase'
      AND conv_time >= event_time
      AND event_time >= conv_time - INTERVAL 14 DAY
)
SELECT
    channel,
    round(sum(conv_value / journey_len))               AS linear_idr,
    round(sumIf(conv_value, touch_asc  = 1))           AS first_touch_idr,
    round(sumIf(conv_value, touch_desc = 1))           AS last_touch_idr,
    round((sumIf(conv_value, touch_desc = 1) - sumIf(conv_value, touch_asc = 1))
          / sumIf(conv_value, touch_asc = 1) * 100, 1) AS last_vs_first_pct
FROM journeys
GROUP BY channel
ORDER BY linear_idr DESC;
