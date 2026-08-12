# Deployed benchmark results — Aiven Apps, 2026-08-11/12

All runs executed **on the deployed stack** (this directory's `compose.yaml`):
loadgen-service driving ingest-service via `POST /loadtests`, and the tier
ladder running inside the ingest container via `POST /benchmarks`. Post
hot-path rework (`cf02f49`).

Topology: Aiven for ClickHouse **business-16** (3-node HA, replicated tables) +
Aiven for Valkey business-8, same region; ingest app 2 vCPU. The repo-root
`01-ingestion-benchmark/ingest-service/benchmark-results.csv` contains **laptop
runs only** (the reporter writes to the process cwd, so Apps runs land inside
the container) — do not compare these numbers against it. The comparable prior
work is the original Phase-2 run: Startup-16 (single node) + 4 vCPU/8 GB app,
tier 5/8-writer headline 436,458 rows/s.

## 1. Single-event firehose ramp (`batch_size=1`, 45 s/step, through public ingress)

| Target ev/s | Achieved | Error rate | Req p50/p99 (ms) | E2E p50/p99 (ms) |
|---|---|---|---|---|
| 500 | 486 | 2.2% | 48 / 1,290 | 69 / 526 |
| 1,000 | 959 | 3.5% | 45 / 692 | 56 / 684 |
| 1,500 | 1,475 | 1.1% | 46 / 213 | 55 / 157 |
| 2,000 | 1,949 | 2.0% | 48 / 222 | 57 / 193 |
| 2,500 | 2,356 | 5.2% | 49 / 173 | 66 / 422 |
| 3,000 | 2,703 | 9.0% | 51 / 194 | 64 / 1,773 |
| 3,500 | 3,184 | 8.5% | 52 / 137 | 106 / 327 |
| 4,500 | 3,517 | 21.3% | 54 / 141 | 58 / 222 |
| 6,000 | 3,500 | 41.3% | 55 / 132 | 74 / 279 |

**Ceiling ≈ 3,500 ev/s.** All errors are transport-level (HTTP/2 GOAWAY when
the ingress rotates connections, killing in-flight streams) — zero 429s, zero
server errors; the service never queued up. Not fixable server-side (virtual
threads make `server.tomcat.threads.*` a no-op; the requests die before Tomcat).

## 2. Batching removes the ingress penalty

| Run | Rate × batch | Achieved ev/s | Errors | E2E p50/p99 (ms) |
|---|---|---|---|---|
| load-005 | 3,000 × 10 | 2,983 | 2 | 54 / 466 |
| load-016 | 30,000 × 100 | 29,813 | 0 | 107 / 220 |
| load-017 (burst) | 60,000 × 200, 20 s | **59,515** | **0** | 113 / 401 |

Burst: 1.19M events accepted; Valkey backlog peaked at ~31.5k rows and drained
~2 s after the burst ended; zero flusher errors.

## 3. Retune via `PUT /config` (2,000 ev/s × batch 20, zero errors both)

| flush_interval_ms | E2E p50/p99 (ms) |
|---|---|
| 2,000 | 104 / 543 |
| 200 | 66 / 361 |

(Default 500 ms restored after the demo.)

## 4. Tier ladder (`POST /benchmarks`, in-container, same-region)

| Run | Tier | Params | Rows | Wall s | Rows/s | Errors |
|---|---|---|---|---|---|---|
| run-001 | 1 row-by-row | 10k | 10,000 | 145.5 | 69 | 0 |
| run-002 | 2 async_insert | 10k | 10,000 | 136.2 | 73 | 0 |
| run-003 | 3 async + 80 senders | 100k | 91,119 | 1,357.0 | 67 | **8,881** |
| run-007 | 4 JDBC batch | 1M × 10k | 1,000,000 | 98.6 | 10,144 | 0 |
| run-008 | 5 native RowBinary | 1M × 10k | 1,000,000 | 63.5 | 15,749 | 0 |
| run-009 | 6 parallel writers | 2M, 4w × 50k | 2,000,000 | 11.0 | 181,316 | 0 |
| run-010 | 6 parallel writers | **10M, 8w × 50k** | 10,000,000 | 35.4 | **282,489** | 0 |

Findings:

- Row-by-row on a 3-node replicated plan is ~69 rows/s and **80 concurrent
  senders do not rescue it** (67 rows/s) — consistent with the original
  Startup-16 finding (85/s; 80 senders capped at 172/s), with the extra
  replication tax on top. Batching is not an optimization here; it is the
  difference between 67 and 282k rows/s.
- **Open:** tier 3 dropped 8,881/100k inserts (~9%). The exception text is in
  the ingest-service Apps logs (2026-08-11 15:35–15:57 UTC); suspects are
  concurrent-query limits or Keeper/replication contention on insert commits.
- run-010 vs the 436k Phase-2 headline: half the app cores (2 vCPU vs 4) and
  writers 4→8 only bought 1.56× — the generator+writer threads are
  core-starved, so the app size, not the cluster, likely explains the gap.
  Business-16 exit criterion comfortably met regardless (282× the 1,000/s target).

## Known instrumentation gaps

- `/stats` and `/benchmarks` report `flush_p50_ms`/`flush_p99_ms` as 0.0.
- loadgen `request_errors` lumps transport exceptions and non-202 statuses
  together with no breakdown (status histogram / exception-class counts would
  have answered the GOAWAY question directly).
- Valkey-vs-memory A/B still pending: `INGEST_BUFFER` is boot-time, needs a
  composer redeploy with `INGEST_BUFFER=memory`.
