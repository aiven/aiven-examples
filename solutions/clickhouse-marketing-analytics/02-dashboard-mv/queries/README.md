# queries — two tracks, one benchmark

One SQL file per demo chart, matching the 8 use cases in Tinybird's
[real-time marketing dashboards on ClickHouse](https://www.tinybird.co/blog/clickhouse-marketing-dashboards)
article. The suite is kept as two parallel tracks compared 1:1 by the
benchmark harness (`../bench/`):

- **`naive/`** — the Tinybird article's SQL, **verbatim**. The only adaptation
  is the table name (`marketing_events` → `campaign_events`; our shared schema
  uses the article's column set). Exceptions are declared in file headers:
  Q5's published query does not execute in ClickHouse (aggregate in a GROUP BY
  key) and degenerates its own retention grid, so `naive/q5` is the minimal
  executable correction of the same self-join shape — every fix documented.
  This track is the honest "what everyone writes first" baseline. Do not
  optimize it.
- **`optimized/`** — our fix for each query, one of three kinds (the header of
  each file names the bottleneck and the fix):
  - **rollup + MV** (I/O-bound aggregations — Q1, Q2, Q4, Q6, Q8): read a
    pre-aggregated `AggregatingMergeTree` table (`../ddl/01`, `../ddl/04`)
    that a materialized view maintains on every insert block.
  - **query rewrite** (CPU-bound journey queries — Q3, Q5): build each user's
    journey once with grouped arrays + `ARRAY JOIN` instead of window sorts /
    self-joins.
  - **projection** (Q3, Q5, stacked on the rewrite): `user_journey`
    (`../ddl/05`) re-sorts the journey columns by `(user_id, event_time)`;
    the planner picks it up with the SQL untouched.
  - Q7 needs none (partition pruning already covers it); its `optimized/` copy
    is identical by design.

Every naive/optimized pair must return **identical answers** on the same data.
The rollups store `uniq` states — the same estimator the naive queries call —
so even the approximate uniq columns match sketch-for-sketch. The equality
gate in the benchmark harness enforces this.

Run one file locally:

```sh
docker exec -i clickhouse-marketing-analytics-clickhouse-1 \
  clickhouse-client --password local --time --multiquery \
  < 02-dashboard-mv/queries/naive/q3_multi_touch_attribution.sql
```

Timings for both tracks, idle and under the day-90 live stream, are produced
by `../bench/run_suite.py` into `../bench/results/` — the article quotes those
CSVs and nothing else.
