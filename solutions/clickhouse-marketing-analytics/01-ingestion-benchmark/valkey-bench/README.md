# valkey-bench — the Valkey-path mini-benchmark harness

Measures the three numbers the buffered architecture promises: **ingest rate**
(events/s through `POST /events` → `XADD`), **flusher throughput** (rows/s
drained into ClickHouse via the consumer group), and **end-to-end latency**
(event accepted → queryable, p50/p99). Also demos the runtime retune: PUT a new
batch geometry mid-run and watch the stats move.

Requires: `k6` (`brew install k6`), the `clickhouse` client, `jq`, and a
running ingest service in valkey mode.

## Run it locally (harness check)

```bash
# from the repo folder root
docker compose up -d                       # ClickHouse + Valkey
cd 01-ingestion-benchmark/ingest-service
mvn spring-boot:run -Dspring-boot.run.arguments="--buffer=valkey" &

cd ../valkey-bench
SCENARIO=smoke RETUNE_AT=15 ./run-bench.sh
```

`smoke` is a 30-second tooling check, not a benchmark. The real scenarios are
`steady` (~2,000 devices, 1–2.5k events/s, 4 min) and `burst` (a push-campaign
blast ramping to 20,000 devices).

## Run it against Aiven

The service should run **next to the data** (Aiven Apps, same region as
ClickHouse + Valkey — see the root README); driving k6 from a laptop
benchmarks your uplink, same lesson as the ladder. From wherever the driver
runs:

```bash
APP_URL=https://<app-host> \
INGEST_API_KEY=<key> \
CH_HOST=<clickhouse-host> CH_PORT=<native-port> CH_SECURE=--secure \
CH_USER=avnadmin CH_PASSWORD=<password> \
SCENARIO=steady RETUNE_AT=120 ./run-bench.sh
```

(The probe's ClickHouse credentials only need SELECT + INSERT; `demo_ingest`
works.)

## What it produces (`results/<timestamp>-<scenario>/`)

| File | Contents |
|---|---|
| `k6-summary.json`, `k6.log` | accepted/rejected events, request latencies |
| `stats.csv` | `GET /stats` sampled every 5 s: rows flushed, batches, errors, stream length (backlog), pending, live tuning |
| `latency.csv` | one row per probe event: end-to-end latency ms (blank = timed out) |
| `stats-before/after.json` | full `/stats` snapshots bracketing the run |

The closing summary prints events accepted, rows flushed, remaining
backlog/pending, and latency p50/p99. Sanity invariant: rows flushed ≈ events
accepted + probe samples; `pending` must be 0 after the drain.

## How the pieces work

- **`latency-probe.sh`** POSTs one marker event per second (unique
  `campaign_id`) and polls ClickHouse until it is queryable — the full
  XADD → XREADGROUP → bulk insert → visible path, measured honestly from the
  producer's side. Expect roughly `flush_interval + insert time`.
- **`run-bench.sh`** orchestrates probe + `/stats` sampler + k6, with an
  optional `RETUNE_AT`/`RETUNE_BODY` mid-run `PUT /config`.
- **`GET /stats`** (valkey mode only) is the observation point: flusher
  counters since start, the tuning in force, and stream health — a growing
  `stream.length` means producers are outrunning the flushers; non-zero
  `pending` in steady state means a consumer died and its entries await
  `XAUTOCLAIM`.

Scaling datapoints worth capturing: `VALKEY_FLUSHERS=N` runs N flusher
workers inside one instance (each its own consumer in the group — the tier 6
parallel-writers pattern), and 1 vs 2–3 app instances scale the same way.
Local reference from a 3M single-event drain: 1 flusher ≈ 107k rows/s
end-to-end, 4 flushers ≈ 333k rows/s — right in local tier 6 territory, while
also paying the stream-decode overhead.
