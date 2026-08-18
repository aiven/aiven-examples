-- Q4 optimized — reads funnel_rollup (ddl/04) instead of scanning the raw
-- table. Bottleneck of the naive version: I/O — four conditional uniqs over
-- a 30-day raw window. Fix: one uniq state column serves visitors and every
-- funnel stage via uniqMergeIf on the rollup's event_type key.
--
-- Same output shape as queries/naive/q4_conversion_funnel.sql.
SELECT
    campaign_id,
    channel,
    n_visitors                                          AS visitors,
    n_leads                                             AS leads,
    n_trials                                            AS trial_starts,
    n_purch                                             AS purchasers,
    round(n_leads / n_visitors * 100, 1)                AS visitor_to_lead_pct,
    round(n_purch / nullIf(n_leads, 0) * 100, 1)        AS lead_to_purchase_pct
FROM
(
    SELECT
        campaign_id,
        channel,
        uniqMerge(users)                                AS n_visitors,
        uniqMergeIf(users, event_type = 'lead')         AS n_leads,
        uniqMergeIf(users, event_type = 'trial_start')  AS n_trials,
        uniqMergeIf(users, event_type = 'purchase')     AS n_purch
    FROM funnel_rollup
    WHERE day >= today() - 30
    GROUP BY campaign_id, channel
    HAVING n_visitors >= 100
)
ORDER BY visitors DESC;
