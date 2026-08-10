-- Q2 optimized: reads keyword_rollup (ddl/04) instead of scanning 61.8M raw
-- paid_search rows. uniq_sessions/uniq_users are uniqCombined(12) estimates
-- (~1% vs the original's uniq() estimates -- see the rollup's header for the
-- measured variant matrix); purchases, revenue and the top-50 ordering are
-- exact. uniq_* names follow the Q1 convention (aliases must not shadow the
-- rollup's state columns or the -Merge calls resolve to the alias and fail).
SELECT
    keyword,
    ad_group,
    uniqCombinedMerge(12)(sessions)                          AS uniq_sessions,
    uniqCombinedMerge(12)(users)                             AS uniq_users,
    sumIf(events, event_type = 'purchase')                   AS purchases,
    round(sumMergeIf(revenue, event_type = 'purchase'))      AS revenue_idr,
    round(sumMergeIf(revenue, event_type = 'purchase') / uniqCombinedMerge(12)(sessions), 2) AS revenue_per_session
FROM keyword_rollup
GROUP BY keyword, ad_group
HAVING uniq_sessions >= 50
ORDER BY revenue_idr DESC
LIMIT 50;
