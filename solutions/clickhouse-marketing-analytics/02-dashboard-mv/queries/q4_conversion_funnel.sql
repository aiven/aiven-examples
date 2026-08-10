-- Q4 Conversion funnel: visitor -> lead -> trial -> purchase with drop-off
-- percentages, per campaign (top 20 by traffic).
SELECT
    campaign_id,
    any(channel)                                    AS channel,
    uniqCombinedIf(14)(user_id, event_type = 'page_view')   AS visitors,
    uniqCombinedIf(14)(user_id, event_type = 'lead')         AS leads,
    uniqCombinedIf(14)(user_id, event_type = 'trial_start')  AS trials,
    uniqCombinedIf(14)(user_id, event_type = 'purchase')     AS purchases,
    round(leads    / nullIf(visitors, 0) * 100, 1)  AS visitor_to_lead_pct,
    round(trials   / nullIf(leads, 0)    * 100, 1)  AS lead_to_trial_pct,
    round(purchases / nullIf(trials, 0)  * 100, 1)  AS trial_to_purchase_pct
FROM campaign_events
WHERE campaign_id != ''
GROUP BY campaign_id
ORDER BY visitors DESC
LIMIT 20;
