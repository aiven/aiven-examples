# queries — the tinybird-suite demo queries

One SQL file per demo chart, matching the 8 use cases in Tinybird's
[real-time marketing dashboards on ClickHouse](https://www.tinybird.co/blog/clickhouse-marketing-dashboards)
article. Timings: best of two runs, local Docker
CH 26.3, 340.7M rows (May 2026 – Aug 7 2026), metrics from `system.query_log`.

| File | Chart | Best s | Scanned |
|---|---|---|---|
| `q1_campaign_performance.sql` | daily users/purchases/revenue/AOV per channel, last 30d | 0.62 | 42k rows (0.01%) — reads `daily_campaign_rollup`, the MV demo point |
| `q2_keyword_paid_search.sql` | revenue per session by keyword/ad_group (`HAVING sessions >= 50` verbatim) | 2.18 | 61.8M (18%) — PK prune on channel |
| `q3a_multi_touch_attribution.sql` | linear vs first vs last-touch credit — **recommended** array formulation | 3.71 | 562.8M (165%: purchaser subquery is a 2nd pass) |
| `q3b_multi_touch_attribution_window.sql` | same models, the blog's window-function shape (fidelity variant) | 11.32 | same scan, 3.5× the CPU (51.4s vs 14.8s) — window sorts |
| `q4_conversion_funnel.sql` | visitor → lead → trial → purchase drop-offs per campaign | 1.35 | 231M (68%) |
| `q5_cohort_retention.sql` | weekly cohorts × weeks retained, by acquisition channel | 5.78 | 340.7M (100%) — single-scan ARRAY JOIN, no self-join |
| `q6_landing_page_seo.sql` | conversion by traffic source on the same landing pages | 2.87 | 187.7M (55%) |
| `q7_email_analytics.sql` | hourly sends/opens/clicks + open & click-to-open rates, last 7d | 0.03 | 8.7M (2.6%) — time filter prunes partitions |
| `q8_email_list_health.sql` | unsub/bounce alerts — only the 3 bad segments say ALERT | 0.19 | 102.5M (30%) — LowCardinality columns, 0.3 GB |

Q3.A vs Q3.B is a deliberate pair: identical answers (±1%, multi-purchase
edge), but the array formulation builds each journey once instead of sorting
the event stream through several window passes — the demo talking point for
"the blog's query, restructured for 300M+ rows".

Run locally:

```sh
docker exec -i clickhouse-marketing-analytics-clickhouse-1 \
  clickhouse-client --password local --time --multiquery < 02-dashboard-mv/queries/q3a_multi_touch_attribution.sql
```

Validated against the generated backfill (validation gate: every chart must show
a demo-worthy shape — none flat or uniform).

## optimized/ — the optimized variants

The naive files above are frozen as the baseline. `optimized/` holds the
Optimization pass: **four per-chart rollups** (`shared/schema/04_query_rollups.sql`) extend
the Q1 materialized-view pattern to Q2/Q4/Q6/Q8, and the **user_journey
projection** (`shared/schema/05_user_journey_projection.sql`) accelerates Q3.A/Q3.B/Q5
with their SQL untouched (the planner picks it up automatically — the
`optimized/` copies of Q3.A/Q5 are the same SQL, kept for their measured
variant-matrix headers). Raw-table DDL, ingest code and results unchanged;
only Q2's two uniq columns become uniqCombined(12) estimates (≤3.5% observed,
top-50 selection and revenue exact).

| Query | Aiven 26.3 before → after (median of 5, wall) | Local 26.3 after (median of 5) |
|---|---|---|
| Q2 keyword paid search | 5.80 → **0.81 s** (7.2×) | 0.40 s |
| Q3.A attribution | 9.98 → **8.57 s** (projection, SQL untouched) | 3.99 s |
| Q3.B attribution (article's SQL) | 32.56 → **25.19 s** (projection, free) | 7.92 s |
| Q4 conversion funnel | 3.37 → **0.36 s** (9.4×) | 0.12 s |
| Q5 cohort retention | 13.45 → **11.33 s** (projection, SQL untouched) | 4.23 s |
| Q6 landing page / SEO | 8.22 → **1.24 s** (6.6×) | 0.45 s |
| Q8 email list health | 0.65 → **0.04 s** (16×) | 0.003 s |

Q1/Q7 unchanged (already rollup-backed / partition-pruned). Storage per node:
rollups +0.6 GiB, projection +2.5 GiB on a 12.1 GiB table. Rejected-variant
measurements (exact-uniq rollups, dropping Q3.A's purchaser subquery,
`optimize_aggregation_in_order`) are documented in the DDL/query headers.
