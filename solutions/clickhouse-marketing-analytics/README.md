# ClickHouse Marketing Analytics

Real-time marketing analytics on Aiven for ClickHouse®, built end to end: a
max-throughput ingestion benchmark, a `campaign_events` dataset with a synthetic
generator, and a dashboard query suite with pre-aggregation optimizations.

The origin story: a customer in the marketing business trialing ClickHouse hit a
wall with data insertion — row-by-row JDBC inserts erroring out under load and
topping out around 1,000 rows/s. They asked whether Aiven for ClickHouse could
sustain 100,000 inserts/s. The answer, on a single-node Startup-16 plan, was
**436,458 rows/s sustained with zero errors** — not from a bigger machine, but
from the right insert pattern. This repo reproduces that journey.

## Layout

| Path | Contents |
|---|---|
| [shared/schema/](shared/schema/) | `campaign_events` DDL (the customer's exact schema), `daily_campaign_rollup` MV, live diagnostics queries, rollup/projection objects |
| [shared/datagen/](shared/datagen/) | journey-based synthetic event generator (backfill → Parquet, live mode) |
| [shared/loadgen/](shared/loadgen/) | k6 scenario simulating a mobile fleet emitting single events: steady state + push-campaign burst |
| [01-ingestion-benchmark/](01-ingestion-benchmark/) | Spring Boot 3.5 / Java 25 benchmark harness; the ladder behind `--tier=1..6` (`--tier=0` = buffered REST pipeline) |
| [02-dashboard-mv/](02-dashboard-mv/) | the 8 dashboard queries (naive + optimized variants) |
| [infra/](infra/) | Terraform: Aiven for ClickHouse (26.3, `business-16`) + Aiven for Valkey (9.1, `business-8`) — on Aiven, SQL `CREATE DATABASE` works for `avnadmin` only (Replicated engine); other users go via console/API/provider ([limitations](https://aiven.io/docs/products/clickhouse/reference/limitations)) |
| [docker-compose.yml](docker-compose.yml) | local fallback: ClickHouse 26.3 (schema auto-applied on first start) + Valkey 9.1 |

## The ingestion ladder

Six techniques, each changing exactly one variable over the previous one, from
the customer's original row-by-row JDBC pattern to parallel native-client
streaming. All runs zero errors, row counts verified server-side, deterministic
seeded data.

**Environments:** Local Docker = ClickHouse 26.3 on an M-series laptop.
Laptop → Aiven = same code over TLS/WAN (consumer uplink — those numbers mostly
measure the uplink). **Same-region** = the service deployed on Aiven Apps next to
the ClickHouse service (Startup-16), driven via the remote benchmark API; this is
what production looks like, so these are the headline numbers.

| Tier | Technique | Reproduce with | Laptop → Aiven | **Aiven Apps (same-region)** | Local Docker |
|---|---|---|---|---|---|
| 1 | Row-by-row JDBC (the original code) | `--tier=1` | 25 | **85** (p50 10 ms/insert) | 226 |
| 2 | `async_insert` tuned, sequential | `--tier=2` | 16 | **79** — same as tier 1, see finding 1 | 180 |
| 3 | async_insert × 80 concurrent senders | `--tier=3` | 92 | **172** (p50 382 ms/insert!) | 619 |
| 4 | `jdbcTemplate.batchUpdate` @10k | `--tier=4` | 7,073 | **52,632** | 151,624 |
| 5 | client-v2 RowBinary stream + LZ4 @10k | `--tier=5` | 9,231 | **66,521** | 92,573 (217k w/ `async_insert=0`, finding 8) |
| 6 | Parallel native writers, 8 × @50k | `--tier=6 --writers=8 --batch-size=50000` | 37,595 (@10k) | **436,458** — 10M rows in 23 s | 608,021 (324k @10k) |

Flags, the remote API's `tier` field, the CSV run labels, and the code
packages all share this same 1–6 numbering (`--tier=0` is the off-ladder
buffered REST pipeline below). Every number above is traceable per run in
[`benchmark-results.csv`](01-ingestion-benchmark/ingest-service/benchmark-results.csv),
and the same numbers are retrievable from a deployed service via
`GET /benchmarks`.

Three additional runs sit outside the ladder — either a variant of a rung or
not an insert technique at all:

| Run | Why it's not a rung | Reproduce with | Laptop → Aiven | **Same-region** | Local Docker |
|---|---|---|---|---|---|
| JSONEachRow variant @10k | tier 5 with a different wire format (finding 5) | `--tier=5 --format=JSONEachRow` | 6,372 | **57,386** | 85,860 |
| 4 parallel writers @10k | tier 6's intermediate step | `--tier=6 --writers=4` | 33,513 | **107,704** | 147,947 |
| Buffered REST pipeline | an ingestion *service*, not an insert technique: REST endpoint → bounded in-memory queue → size-or-time flush → batch insert | `--tier=0` | 6,723 | **80,337** | 122,549 |

The buffered REST run deserves the longer note: it answers how single-event
producers meet the batching requirement, and it preserves the batch economics
(80.3k rows/s same-region) while giving devices something they can actually
call — at the cost that the buffer dies with the app. The durable version of
that idea is the post-ladder production architecture below.

### Findings

1. **The JDBC `async_insert` gotcha is real and provable live.** Every
   jdbc-driver insert lands with `async_insert=0` in `system.query_log` even
   when the URL sets `clickhouse_setting_async_insert=1` — the server disables
   async for INSERTs whose data is inlined in the query text, which is how
   prepared statements ship. Proper async from Java needs body-separated
   inserts = the tier 5 client-v2 path.
2. **Uncompressed batches are WAN-bound from a laptop.** A 10k-row batch is
   ~3 MB of VALUES text. With LZ4 request compression (`decompress=true` on the
   JDBC URL): 440 → **7,073 rows/s**, a 16x jump from one connection option.
3. **Concurrency cannot rescue per-event inserts.** 80 concurrent senders buy
   ~2x, not 80x: each replicated single-row INSERT costs ~380 ms p50
   *server-side* under that concurrency, and each eats a concurrent-query slot.
   Batching (tier 4) is a **306x** jump over that with ~20 lines of code.
4. **A single laptop TLS stream tops out ~9–10k rows/s regardless of batch
   size** — bandwidth-bound, not round-trip-bound. Benchmark from where the app
   will actually run; colocate the ingestion service with the database in
   production (Aiven Apps, or any VM/K8s in the same region).
5. **RowBinary beats JSONEachRow by 1.08–1.45x** on the same rows — fewer bytes,
   no server-side text parsing. (JSONEachRow needs
   `date_time_input_format=best_effort` for ISO-8601 `DateTime64`; the service
   sets it per insert.)
6. **Row-by-row manufactures `too many parts` by design.** Each insert creates
   one part; mid-run, ~1,700 active parts with merges churning constantly
   (watch it live with
   [shared/schema/03_diagnostics.sql](shared/schema/03_diagnostics.sql)). One
   batch = one part makes the failure mode disappear at the source.
7. **Parallel writers multiply until something else saturates.** Same-region:
   4 writers @10k = 107.7k rows/s; 8 writers @50k = **436,458 rows/s — 10M rows
   in 23 s, 0 errors**. The Startup-16 absorbed it with headroom; 436k is where
   the benchmark stopped, not where ClickHouse stopped.
8. **ClickHouse 26.3's server-wide `async_insert=1` default silently slows
   batch inserts.** Body-separated client-v2 batches *do* engage it (unlike
   JDBC inline VALUES, finding 1) and wait in the async buffer. Pinning
   `async_insert=0` restored single-stream local throughput 92.6k → **217k
   rows/s** and lifted 8w@50k from 608k to 651k. Async insert is for many tiny
   writers; production batch paths should set `async_insert=0` explicitly. The
   ladder table keeps server-default numbers (that's what an unmodified Aiven
   26.3 service runs).

## After the ladder: durable buffering with Valkey Streams

The ladder assumes you have 10,000 rows in hand to batch. Real producers (web
frontends, mobile apps, backend services) emit one event at a time, so
something between them and ClickHouse must collect events into batches. An
in-memory queue (the buffered REST run above) does that — until the app crashes and takes the
buffer with it. Kafka is the classic durable answer; the middle ground, when
topics/partitions/consumer-lag operations are more platform than you want to
run, is **Aiven for Valkey™ with Valkey Streams as the buffer**. That is what
`POST /events` uses in production mode (`INGEST_BUFFER=valkey`):

1. The receiver `XADD`s each event onto a stream — sub-millisecond, and the
   buffer is centralized: shared by all app instances, surviving any of them.
2. A background flusher *inside the same app* consumes via a consumer group:
   `XREADGROUP COUNT <batch_size> BLOCK <flush_interval>`, so it wakes with up
   to a full batch or whatever arrived within the interval.
3. It bulk-inserts through the ladder's winning path (client-v2 RowBinary +
   LZ4, `async_insert=0` pinned per finding 8), `XACK`s the batch, and trims
   with `XTRIM MINID` up to the oldest un-acked entry — exactly what is
   confirmed in ClickHouse gets deleted, nothing else.

Scaling out needs no coordination code: every instance joins the same consumer
group under a unique consumer name (the pod name), Valkey delivers each entry
to exactly one consumer, and N instances = N parallel flushers = N parallel
bulk inserts — precisely the pattern tier 6 proved ClickHouse wants.
If an instance dies mid-flush, its unacked entries sit in the group's pending
list until a survivor reclaims them with `XAUTOCLAIM` (after
`valkey.claim-min-idle-ms`, default 30 s). Delivery is at-least-once;
analytics tolerates the occasional replay, and ClickHouse orders by
`event_time` regardless. Failed inserts are never acked, and `POST /events`
returns 429 once the stream passes `valkey.max-stream-length`, so a ClickHouse
outage stalls ingestion instead of losing events or filling Valkey's memory.

Batch geometry is runtime-tunable, with the live values in Valkey itself
(hash `ingest:config`) so one update retunes every instance immediately — no
redeploy, no restart, and the tuning survives deploys:

```bash
curl -s localhost:8080/config -H "X-API-Key: $INGEST_API_KEY"
curl -s -X PUT localhost:8080/config -H 'Content-Type: application/json' \
  -H "X-API-Key: $INGEST_API_KEY" \
  -d '{"batch_size": 50000, "flush_interval_ms": 1000}'
```

Caveat, stated plainly: Valkey persistence is snapshot-based, not a replicated
commit log — a hard crash of the Valkey service can lose a short window of
events. For marketing analytics that trade is usually acceptable; when the
events become revenue-critical, Apache Kafka® slots into exactly this point in
the architecture and nothing downstream changes.

## Run it

```bash
# Local ClickHouse
docker compose up -d clickhouse    # creates the db + applies shared/schema/ on first start

cd 01-ingestion-benchmark/ingest-service
mvn spring-boot:run -Dspring-boot.run.arguments="--tier=1 --rows=10000"

# The full ladder (add --spring.main.web-application-type=none to exit after the run):
#   --tier=0 --rows=200000                                  # buffered REST pipeline benchmark
#   --tier=5 --rows=1000000 [--batch-size=N] [--format=JSONEachRow]
#   --tier=6 --rows=2000000 --writers=8 --batch-size=50000
# REST service mode: start with no --tier, then POST /events (see shared/loadgen/README.md)
#   default: in-memory buffer (the buffered REST run)
#   production architecture: docker compose up -d valkey, then add --buffer=valkey

# Against Aiven: put credentials in .env.aiven at the repo root
# (git-ignored; template in .env.aiven.example)
cp ../../.env.aiven.example ../../.env.aiven   # then fill in host/port/password
set -a; source ../../.env.aiven; set +a
mvn spring-boot:run -Dspring-boot.run.arguments="--tier=1 --rows=10000 --spring.profiles.active=aiven"
```

While the tier 1 baseline (`--tier=1`) runs, watch the failure mode live with
[shared/schema/03_diagnostics.sql](shared/schema/03_diagnostics.sql)
(`system.parts` explosion, merge pressure, delayed/rejected inserts).

## Remote benchmark API (for Aiven Apps / any headless deploy)

Laptop benchmark numbers are uplink-bound (~37k rows/s vs 608k local), so the
headline runs happen with the service deployed **next to the data** — Aiven Apps
in the same region as the ClickHouse service. There is no terminal there, so the
whole ladder is drivable over HTTP; start the service with no `--tier` and use:

```bash
# Fire a run (only "tier" is required; everything else falls back to ingest.* defaults)
curl -s -X POST localhost:8080/benchmarks -H 'Content-Type: application/json' \
  -H "X-API-Key: $INGEST_API_KEY" \
  -d '{"tier": 6, "rows": 10000000, "writers": 8, "batch_size": 50000}'
# -> 202 {"id":"run-001-tier6","state":"RUNNING",...}  (Location: /benchmarks/run-001-tier6)

curl -s -H "X-API-Key: $INGEST_API_KEY" localhost:8080/benchmarks/run-001-tier6  # live progress / result
curl -s -H "X-API-Key: $INGEST_API_KEY" localhost:8080/benchmarks                # all runs this process
```

**Auth:** set `INGEST_API_KEY` (e.g. `openssl rand -hex 32`) and every endpoint
except `/actuator/health` requires that value in an `X-API-Key` header —
constant-time compared, 401 otherwise. Unset = open (local dev/CLI); starting
the `aiven` profile without a key logs a loud warning, so never do that on a
public deploy.

Request fields (`tier` uses the same 1–6 numbering, 0 = buffered REST
pipeline): `rows`/`seed` (all), `concurrency` (tier 3, default 80),
`batch_size` (tiers 4–6 and 0), `format` = `RowBinary`|`JSONEachRow` (tiers
5–6), `writers` (tier 6), `buffer_capacity`/`flush_interval_ms` (tier 0).
Status responses
stream live `rows_inserted` / `progress_pct` / `rows_per_sec` while running and
keep the final numbers (plus `flush_p50_ms`/`flush_p99_ms`/`errors`) once `state`
is `COMPLETED`; failures land as `state=FAILED` with the exception in `error`.
One run executes at a time — a POST while busy returns **409** with the active
run, so overlapping runs can't corrupt each other's numbers.

### Deploy to Aiven Apps

[01-ingestion-benchmark/ingest-service/compose.yaml](01-ingestion-benchmark/ingest-service/compose.yaml)
is the Aiven Apps recipe (build context +
[Dockerfile](01-ingestion-benchmark/ingest-service/Dockerfile)); supply the
`AIVEN_CH_*` variables as Apps env/secrets — nothing is baked into the image.
The platform probes `/actuator/health` on port 8080, and SIGTERM triggers
Spring's graceful shutdown (the in-memory buffer drains before exit). Local
container smoke test:

```bash
cd 01-ingestion-benchmark/ingest-service
docker compose --env-file ../../.env.aiven up --build
```

## Dashboard queries

[02-dashboard-mv/queries/](02-dashboard-mv/queries/) holds the 8 demo queries
(campaign performance, keyword paid search, multi-touch attribution, conversion
funnel, cohort retention, landing-page SEO, email analytics, email list health),
with [optimized/](02-dashboard-mv/queries/optimized/) variants backed by the
rollup and projection objects in [shared/schema/](shared/schema/) — 7–16x faster
on the dashboard charts. Generate data for them with
[shared/datagen/](shared/datagen/).

## Tests

```bash
cd 01-ingestion-benchmark/ingest-service && mvn test   # Testcontainers: real ClickHouse, real schema files
```

Integration tests verify: DDLs apply cleanly, the schema matches the customer's
exact table (16 columns, `campaign_id LowCardinality(String) DEFAULT ''`), the
rollup MV populates on insert, all 6 tiers are registered, and every implemented
tier end-to-end against a real ClickHouse — including the buffered REST pipeline's POST /events →
queryable <2 s latency contract and 429-on-full-queue backpressure, tier 5's
RowBinary/JSONEachRow value fidelity (DateTime64 millis, Nullable columns), and
tier 6's no-lost-rows accounting across parallel writers. The Valkey
architecture is tested end to end against a real Valkey container: POST
/events → XADD → consumer-group flusher → queryable in ClickHouse, plus the
bounds-checked GET/PUT /config round trip.

## Notes

- `campaign_events` stays byte-identical to the customer's original DDL
  (the tinybird "marketing_events" schema with one deviation: non-Nullable
  `campaign_id`). On Aiven, `ENGINE = MergeTree` is auto-remapped to
  `ReplicatedMergeTree`; the DDL runs unchanged.
- Every tier runs against both local Docker ClickHouse and Aiven via config
  only; every benchmark run emits the rows/s / p50/p99 / errors table.
- No secrets in the repo: credentials go in `.env.aiven` (git-ignored,
  template provided).
