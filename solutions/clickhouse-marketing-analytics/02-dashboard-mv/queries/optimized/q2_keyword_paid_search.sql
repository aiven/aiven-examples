-- Q2 optimized — reads keyword_rollup (ddl/04) instead of scanning the raw
-- paid_search rows (a ~125x reduction in rows read). Honest caveat, measured
-- at 679M: the naive query is ALREADY fast idle-local (~0.5s) because its
-- 14-day window rides the (channel, campaign_id, event_time, ...) sort key —
-- the rollup's case is resource isolation (99% fewer rows touched while
-- ingest and other queries compete), not idle wall time. Compare the
-- idle vs under-load CSVs before quoting either number.
--
-- Same output shape as queries/naive/q2_keyword_paid_search.sql. The naive
-- query computes revenue_per_session from the UNROUNDED revenue sum, so this
-- does too (rev, not the rounded output column).
SELECT
    keyword,
    ad_group,
    n_sessions                              AS sessions,
    n_conversions                           AS conversions,
    round(rev, 2)                           AS revenue,
    round(rev / n_sessions, 2)              AS revenue_per_session
FROM
(
    SELECT
        keyword,
        ad_group,
        uniqMerge(sessions)                       AS n_sessions,
        sum(purchases)                            AS n_conversions,
        sumMerge(revenue)                         AS rev
    FROM keyword_rollup
    WHERE day >= today() - 14
    GROUP BY keyword, ad_group
    HAVING n_sessions >= 50
)
ORDER BY revenue_per_session DESC
LIMIT 100;
