-- Q6 optimized: reads landing_page_rollup (ddl/04) instead of scanning 187.7M
-- raw rows. The rollup keeps every channel; the organic/paid_search/social
-- restriction stays in the query. Same output as queries/q6_landing_page_seo.sql
-- (uniq_sessions naming per the Q1 alias-shadowing convention).
SELECT
    landing_page,
    channel                                                       AS traffic_source,
    uniqCombinedMerge(14)(sessions)                               AS uniq_sessions,
    uniqCombinedMergeIf(14)(users, event_type = 'purchase')       AS purchasers,
    round(uniqCombinedMergeIf(14)(users, event_type = 'purchase')
          / nullIf(uniqCombinedMerge(14)(users), 0) * 100, 2)     AS user_conversion_pct,
    round(sumMergeIf(revenue, event_type = 'purchase'))           AS revenue_idr
FROM landing_page_rollup
WHERE channel IN ('organic', 'paid_search', 'social')
GROUP BY landing_page, traffic_source
ORDER BY landing_page, traffic_source;
