-- Q6 Landing page / SEO: conversion by traffic source on the SAME pages.
-- Keeping organic / paid_search / social separate makes the gap visible
-- (social converts ~half as well as organic; paid_search slightly better).
-- uniqCombined(14) (~0.5% error) instead of uniqExact and PREWHERE on the
-- selective column: 4.6s -> 2.6s on 309M rows, same chart.
SELECT
    landing_page,
    channel                                                        AS traffic_source,
    uniqCombined(14)(session_id)                                   AS sessions,
    uniqCombinedIf(14)(user_id, event_type = 'purchase')           AS purchasers,
    round(uniqCombinedIf(14)(user_id, event_type = 'purchase')
          / nullIf(uniqCombined(14)(user_id), 0) * 100, 2)         AS user_conversion_pct,
    round(sumIf(conversion_value, event_type = 'purchase'))        AS revenue_idr
FROM campaign_events
PREWHERE landing_page IS NOT NULL
WHERE channel IN ('organic', 'paid_search', 'social')
GROUP BY landing_page, traffic_source
ORDER BY landing_page, traffic_source;
