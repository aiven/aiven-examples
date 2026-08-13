# Deployed benchmark results — Aiven Apps, 2026-08-12

Canonical numbers, measured on the **combined deployment** (`combined/compose.yaml`:
ingest-service + loadgen-service colocated in one container, load path =
`http://localhost:8080`, no ingress). App size **4 vCPU / 8 GB**. Aiven for
ClickHouse **business-16** (3-node HA, replicated tables) + Aiven for Valkey
business-8, same region. Post hot-path rework (`cf02f49`).

Reference point throughout: the original Phase-2 exit run — **Startup-16
(single node)**, same 4 vCPU/8 GB app size, tier 5/8-writer headline
436,458 rows/s. Same app, different cluster topology, so deltas below isolate
the 3-node replication cost.

The repo-root `01-ingestion-benchmark/ingest-service/benchmark-results.csv`
contains **laptop runs only** (the reporter writes to the process cwd, so Apps
runs land inside the container) — never compare against it.

## 1. Tier ladder (`POST /benchmarks`, in-container, same-region)

| Run | Tier | Params | Rows | Wall s | Rows/s | Errors |
|---|---|---|---|---|---|---|
| run-001 | 1 row-by-row | 10k | 10,000 | 138.9 | 72 | 0 |
| run-002 | 2 async_insert | 10k | 10,000 | 147.1 | 68 | 0 |
| run-003 | 3 async + 80 senders | 100k | 55,279 | 461.7 | 120 | **44,721** |
| run-004 | 4 JDBC batch | 1M × 10k | 1,000,000 | 13.7 | 73,005 | 0 |
| run-005 | 5 native RowBinary | 1M × 10k | 1,000,000 | 14.2 | 70,250 | 0 |
| run-006 | 6 parallel writers | 2M, 4w × 50k | 2,000,000 | 9.3 | 215,348 | 0 |
| run-007 | 6 parallel writers | **10M, 8w × 50k** | 10,000,000 | 30.5 | **327,862** | 0 |

Findings:

- **Business-16 headline: 327,862 rows/s** (8 writers × 50k, 10M rows, zero
  errors) — 75% of the 436k Phase-2 number on the same app size. The ~25% gap
  is the 3-node replication cost on the batch path. 328× the 1,000/s target.
- **Row-by-row is ~70 rows/s on a replicated plan and concurrency does not
  rescue it**: 80 senders reached 120 rows/s — consistent with the original
  Startup-16 finding (85/s; 80 senders capped at 172/s), replication tax on
  top. Batching is not an optimization here; it is the difference between
  70 and 328k rows/s.
- **Tier 3 fails in a distinctive pattern (open item, reproduced on two
  different app containers → server-side):** the first ~50% of rows inserted
  with zero errors, then mass failure — 44,721 of 100k dropped. Something
  accumulates until ClickHouse starts rejecting (async-insert buffer
  pressure, too-many-parts, or replication queue backlog). The exception
  text is in the ingest-service Apps logs (`run-003-tier3`); suspects above.
  **Update:** the sender sweep (section 1b) localized the onset to between
  20 and 30 concurrent senders.
- Batch-tier numbers are sensitive to cluster state: the same ladder run a
  day earlier, minutes after 3.2M burst rows and a 20-minute tier-3 error
  grind, measured tiers 4/5 at 10k/15.7k rows/s — 4–7× below these. Let
  merges settle before quoting batch numbers.

## 1b. Tier-3 sender sweep (2026-08-12 evening — localizing the tier-3 anomaly)

Tier 3 re-run at increasing sender counts (100k rows, seed 42, same
deployment), stepping by 10 until errors appeared:

| Run | Senders | Inserted | Errors | Wall s | Rows/s |
|---|---|---|---|---|---|
| run-008 | 10 | 100,000 | 0 | 496.8 | 201 |
| run-009 | 20 | 100,000 | 0 | 532.2 | 188 |
| run-010 | 30 | 89,645 | **10,355** | 953.8 | 94 |
| — | 40–80 | not run — threshold found | | | |

- **Error onset is between 20 and 30 concurrent senders** — far below the 80
  of run-003.
- **Degradation precedes failure**: the 30-sender run started at ~210 rows/s
  and decayed continuously (175 → 118 → 94) before errors appeared late in
  the run — consistent with server-side accumulation (async-insert buffer
  pressure / parts backlog / replication queue) rather than a hard
  concurrency limit. The exact mechanism is still open; the exception text is
  in the ingest-service Apps logs (`run-010-tier3`).
- **Concurrency is strictly counterproductive on this path**: 10 senders →
  201 rows/s clean; 20 → 188 clean; 30 → 94 with 10% dropped; 80 (run-003) →
  120 with 45% dropped. The drop rate grows with sender count past the
  threshold, and the row-by-row/async path tops out around ~200 rows/s
  regardless.

## 2. Single-event `/events` ramp (loadgen → localhost, `batch_size=1`, 45 s/step)

| Target ev/s | Achieved | Errors | Req p50/p99 (ms) | E2E p50/p99 (ms) |
|---|---|---|---|---|
| 1,000 | 993 | 0 | 1.5 / 6.7 | 22 / 86 |
| 2,000 | 1,981 | 0 | 1.8 / 5.1 | 12 / 458 |
| 3,500 | 3,476 | 0 | 2.3 / 5.4 | 21 / 54 |
| 5,000 | 4,961 | 0 | 2.8 / 7.5 | 20 / 43 |
| 7,500 | 7,421 | 0 | 3.8 / 19.6 | 24 / 68 |
| 10,000 | **9,501** | 0 | 7.1 / 82 | 27 / 110 |
| 15,000 | 4,100 | 1 | 662 / 6,913 | 69 / 306 |
| 20,000 | 5,079 | 14 | 481 / 5,412 | — |

- **Practical single-event ceiling ≈ 9,500 ev/s** with sender and receiver
  sharing the container. Past 10k the *sender* collapses (request p50 jumps to
  ~500–660 ms) while the pipeline stays healthy — e2e p50 69 ms, Valkey stream
  drained, zero flusher errors — i.e. saturation queueing in the load loop,
  not backpressure.
- Zero transport errors across ~2M events on the localhost path.

## 3. What the ingress was costing (measured 2026-08-11, separate-apps deploy)

The same single-event ramp through the public `*.aiven.app` ingress capped at
**~3,500 ev/s with 8–41% request errors** — all transport-level HTTP/2 GOAWAY
failures (ingress connection rotation killing in-flight streams; zero 429s,
zero server errors; `server.tomcat.threads.*` is a no-op with virtual threads
and the requests die before Tomcat anyway). At the same 3,500 ev/s rate:
request p99 137 ms through the ingress vs 5.4 ms on localhost.

**The end-to-end bottleneck is the delivery leg, never ingest → ClickHouse.**
Batching removes it even through the ingress (3,000 ev/s × batch 10 → 2
errors; 60,000 ev/s × batch 200 for 20 s → 1.19M events, zero errors, Valkey
backlog peaked ~31.5k rows and drained in ~2 s). For "producers cannot batch"
scenarios through an ingress, the client-side answer is batching/retry
budgets — or colocate the producer path like the combined deployment does.

## 4. Runtime retune via `PUT /config` (2,000 ev/s × batch 20, zero errors)

| flush_interval_ms | E2E p50/p99 (ms) |
|---|---|
| 2,000 | 104 / 543 |
| 200 | 66 / 361 |

(Default 500 ms restored after the demo.)

## Known instrumentation gaps

- `/stats` and `/benchmarks` report `flush_p50_ms`/`flush_p99_ms` as 0.0.
- loadgen `request_errors` lumps transport exceptions and non-202 statuses
  together with no breakdown (a status histogram / exception-class count
  would have answered the GOAWAY question directly).
- Valkey-vs-memory A/B still pending: `INGEST_BUFFER` is boot-time, needs a
  composer redeploy with `INGEST_BUFFER=memory`.
