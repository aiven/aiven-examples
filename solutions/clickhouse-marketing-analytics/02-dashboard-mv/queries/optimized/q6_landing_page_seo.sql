-- Q6 optimized — reads landing_page_rollup (ddl/04) instead of scanning the
-- raw table. Bottleneck of the naive version: I/O — the heaviest
-- bytes-per-row query (wide session strings) over a 30-day window. Fix:
-- day-grain rollup; states merge up to the naive query's weekly grain.
--
-- BOUNDED APPROXIMATION (the suite's only one): sessions/unique_users are
-- uniqCombined(14) estimates (~0.5% from truth) compared against the naive
-- query's uniq() estimates (~2% from truth at these cardinalities) — the two
-- estimators can disagree by the sum of their errors, observed ≤3% at 679M
-- rows. Exact-uniq states at this grain are so large the rollup read lost to
-- the raw scan (see the DDL header for the measurement). leads / purchases /
-- revenue and the weekly grouping are exact. The equality gate compares Q6
-- with a 4% ceiling on the uniq columns and pairs rows by dimension key.
SELECT
    landing_page,
    channel,
    week,
    n_sessions                              AS sessions,
    n_users                                 AS unique_users,
    n_leads                                 AS leads,
    n_purchases                             AS purchases,
    round(n_leads / n_sessions * 100, 2)    AS landing_to_lead_pct,
    round(rev, 2)                           AS revenue
FROM
(
    SELECT
        landing_page,
        channel,
        toStartOfWeek(day)                        AS week,
        uniqCombinedMerge(14)(sessions)           AS n_sessions,
        uniqCombinedMerge(14)(users)              AS n_users,
        sum(leads)                                AS n_leads,
        sum(purchases)                            AS n_purchases,
        sumMerge(revenue)                         AS rev
    FROM landing_page_rollup
    WHERE channel IN ('organic', 'paid_search', 'social')
      AND day >= today() - 30
    GROUP BY landing_page, channel, week
    HAVING n_sessions >= 100
)
ORDER BY week DESC, sessions DESC;
