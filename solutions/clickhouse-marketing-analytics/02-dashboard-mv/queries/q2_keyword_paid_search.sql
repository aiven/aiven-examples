-- Q2 Keyword-level paid search: revenue per session by keyword/ad_group.
-- The HAVING sessions >= 50 clause is from the blog verbatim.
SELECT
    keyword,
    ad_group,
    uniq(session_id)                                         AS sessions,
    uniq(user_id)                                            AS users,
    countIf(event_type = 'purchase')                         AS purchases,
    round(sumIf(conversion_value, event_type = 'purchase'))  AS revenue_idr,
    round(sumIf(conversion_value, event_type = 'purchase') / uniq(session_id), 2) AS revenue_per_session
FROM campaign_events
WHERE channel = 'paid_search' AND keyword IS NOT NULL
GROUP BY keyword, ad_group
HAVING sessions >= 50
ORDER BY revenue_idr DESC
LIMIT 50;
