-- Q3.A optimized = the baseline SQL unchanged, accelerated by the
-- user_journey projection (ddl/05). ClickHouse picks the projection
-- automatically (system.query_log `projections` column proves it), so the
-- demo point is: schema work, zero query changes.
--
-- Rewrites we measured and REJECTED (local 26.3, 340.7M rows, 3 runs each):
--   * dropping the purchaser pre-filter subquery + hash agg: 11.7s
--   * dropping it + optimize_aggregation_in_order:            7.0s
--   * this SQL on the projection:                             3.0-3.2s
--   * this SQL with the projection disabled:                  4.9-5.7s
-- Grouping all 8M users costs more than the subquery's second pass, and
-- in-order aggregation trades parallelism for memory it doesn't need here.
WITH journeys AS
(
    SELECT
        user_id,
        arraySort(x -> x.1,
            groupArrayIf((toUnixTimestamp64Milli(event_time), channel),
                         event_type IN ('page_view', 'click') AND campaign_id != '')) AS touches,
        groupArrayIf((toUnixTimestamp64Milli(event_time), conversion_value),
                     event_type = 'purchase')                                         AS purchases
    FROM campaign_events
    PREWHERE event_type IN ('page_view', 'click', 'purchase')
    WHERE user_id IN (SELECT DISTINCT user_id FROM campaign_events WHERE event_type = 'purchase')
    GROUP BY user_id
    HAVING length(touches) > 0 AND length(purchases) > 0
),
credited AS
(
    SELECT
        p.2 AS revenue,
        arrayFilter(t -> t.1 <= p.1 AND t.1 >= p.1 - 14 * 86400000, touches) AS journey
    FROM journeys
    ARRAY JOIN purchases AS p
    WHERE length(arrayFilter(t -> t.1 <= p.1 AND t.1 >= p.1 - 14 * 86400000, touches)) > 0
)
SELECT
    channel,
    round(sum(linear_credit))                        AS linear_idr,
    round(sum(first_credit))                         AS first_touch_idr,
    round(sum(last_credit))                          AS last_touch_idr,
    round((sum(last_credit) - sum(first_credit)) / sum(first_credit) * 100, 1) AS last_vs_first_pct
FROM
(
    SELECT
        t.2                                          AS channel,
        revenue / length(journey)                    AS linear_credit,
        if(t.1 = journey[1].1, revenue, 0)           AS first_credit,
        if(t.1 = journey[-1].1, revenue, 0)          AS last_credit
    FROM credited
    ARRAY JOIN journey AS t
)
GROUP BY channel
ORDER BY linear_idr DESC;
