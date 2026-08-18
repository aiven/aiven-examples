-- Q3 optimized — query rewrite (+ the user_journey projection, ddl/05).
-- Bottleneck of the naive version: CPU, not I/O — the window functions sort
-- each user's event stream several times (row_number ascending, count,
-- max/argMax over the partition). Fix: build each user's journey ONCE with
-- groupArray + arraySort, then ARRAY JOIN the touches. Same three models,
-- same numbers. The user_journey projection re-sorts the journey columns by
-- (user_id, event_time), so the per-user GROUP BY streams in order instead
-- of building a multi-GB hash table — this SQL is picked up automatically,
-- untouched.
--
-- Same output shape as queries/naive/q3_multi_touch_attribution.sql.
-- Faithful to the naive semantics: ALL events of purchasing users in the
-- window count as touches (including the purchase events themselves), and
-- conversion_value = the value at the user's latest-timestamped non-null
-- event (argMax skips NULLs, same as the window argMax). Events sharing an
-- identical millisecond timestamp may order differently than row_number();
-- the equality gate compares the aggregated output, where this cancels out.
WITH per_user AS
(
    SELECT
        user_id,
        arraySort(x -> x.1,
            groupArray((toUnixTimestamp64Milli(event_time), channel, campaign_id))) AS touches,
        argMax(conversion_value, event_time)   AS conv_value
    FROM campaign_events
    WHERE event_time >= today() - 30
      AND user_id IN
      (
          SELECT user_id FROM campaign_events
          WHERE event_type = 'purchase'
            AND event_time >= today() - 30
      )
    GROUP BY user_id
)
SELECT
    channel,
    campaign_id,
    round(sum(conv_value / total_touches), 2)                    AS linear_attributed_revenue,
    round(sumIf(conv_value, touch_position = 1), 2)              AS first_touch_revenue,
    round(sumIf(conv_value, touch_position = total_touches), 2)  AS last_touch_revenue,
    count()                                                      AS touch_count
FROM
(
    SELECT
        t.2                 AS channel,
        t.3                 AS campaign_id,
        idx                 AS touch_position,
        length(touches)     AS total_touches,
        conv_value
    FROM per_user
    ARRAY JOIN touches AS t, arrayEnumerate(touches) AS idx
)
GROUP BY channel, campaign_id
ORDER BY linear_attributed_revenue DESC;
