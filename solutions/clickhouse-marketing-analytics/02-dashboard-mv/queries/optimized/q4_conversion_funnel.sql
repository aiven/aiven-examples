-- Q4 optimized: reads funnel_rollup (ddl/04) instead of scanning 231M raw
-- rows. One uniqCombined(14) state column serves all four funnel stages via
-- uniqCombinedMergeIf on the event_type key. Same output as
-- queries/q4_conversion_funnel.sql.
SELECT
    campaign_id,
    any(channel)                                                AS channel,
    uniqCombinedMergeIf(14)(users, event_type = 'page_view')    AS visitors,
    uniqCombinedMergeIf(14)(users, event_type = 'lead')         AS leads,
    uniqCombinedMergeIf(14)(users, event_type = 'trial_start')  AS trials,
    uniqCombinedMergeIf(14)(users, event_type = 'purchase')     AS purchases,
    round(leads     / nullIf(visitors, 0) * 100, 1)             AS visitor_to_lead_pct,
    round(trials    / nullIf(leads, 0)    * 100, 1)             AS lead_to_trial_pct,
    round(purchases / nullIf(trials, 0)   * 100, 1)             AS trial_to_purchase_pct
FROM funnel_rollup
GROUP BY campaign_id
ORDER BY visitors DESC
LIMIT 20;
