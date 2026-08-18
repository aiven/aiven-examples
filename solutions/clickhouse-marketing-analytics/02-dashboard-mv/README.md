# 02-dashboard-mv — the marketing dashboard, naive vs optimized

Post 2 of the series: nine marketing questions answered over the
`campaign_events` stream, first the way everyone writes them (Tinybird's
published SQL, verbatim), then optimized with the three tools that matter —
**rollups maintained by materialized views** (I/O-bound aggregations),
**query rewrites** (CPU-bound journey queries), and **one projection**
(row-order-bound queries, SQL untouched). Every number in the article is
reproducible from here.

The demo model: "now" = day 90. Days 1–89 (~500M events at full scale) are
batch-backfilled from Parquet; day 90 streams in live through the Post 1
pipeline (livegen → Valkey Streams → in-app flusher → ClickHouse) while the
MVs fire on every inserted block.

## Layout

| Path | What |
|---|---|
| `queries/naive/` | Tinybird's SQL, verbatim (exceptions documented in headers) |
| `queries/optimized/` | our per-query fixes; identical answers, enforced by the gate |
| `ddl/01_daily_campaign_rollup.sql` | the core MV story: Q1's rollup + insert-trigger MV |
| `ddl/04_query_rollups.sql` | four more rollups (Q2/Q4/Q6/Q8) |
| `ddl/05_user_journey_projection.sql` | `user_journey` projection (Q3/Q5, SQL untouched) |
| `bench/` | `run_suite.py` (median-of-5, `system.query_log`, idle+load CSVs), `verify_equality.py` (the naive==optimized gate), `bench_lib.py` (shared measurement) |
| `live/run_day90.sh` | day-90 stream at ~100k events/s into the Post 1 pipeline |
| `grafana/` | importable live board — rollup-backed panels only |
| `report/` | staged-reveal report page + creds-holding proxy + Playwright recorder |

## Quickstart (local)

```sh
# from the solution root
make up                # ClickHouse 26.3 + Valkey; creates campaign_events
make datagen-smoke     # ~14.6M rows, 89 days, deterministic (seed 42)
make optimize          # rollups + MVs (create BEFORE ingest so they fire per block)
make ingest-smoke      # Parquet parts -> HTTP INSERT; MVs maintain rollups live
make project           # add + materialize the user_journey projection
make verify            # equality gate: all 8 naive/optimized pairs must match
make bench             # both tracks, median-of-5 -> bench/results/*_idle.csv
make report            # staged-reveal page on http://localhost:8088
```

Under live load: start the Post 1 ingest service with its Valkey flusher,
then `live/run_day90.sh` (locally use `LIVE_RATE=60000` — the measured
single-VM ceiling; 100k/s is the Aiven-deployment target), and re-run
`make bench BENCH_LABEL=load`. For gap-free sustained pressure during long
benchmark suites, add `--loop` to the livegen invocation (replays day 90
continuously without plan-rebuild pauses).

Aiven: same steps with `CH_URL/CH_USER/CH_PASSWORD` pointed at an Aiven for
ClickHouse Business-16 (`infra/` provisions it; ClickHouse 26.3).

## Rules this folder lives by

- The naive track is never optimized; the optimized track never changes an
  answer (bench/verify_equality.py is the arbiter — rollups store `uniq`
  states, the same estimator the naive queries call, so even approximate
  columns match sketch-for-sketch).
- Every published number traces to `bench/results/*.csv`.
- Screen recordings land in `report/recordings/` which is git-ignored — they
  are article assets, not repo content.
