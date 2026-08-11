# loadgen-service — the load generator as a service

Load tests must run from where the load should come from — same region as the
target, not a laptop behind a consumer uplink (the ladder's environment lesson
applies to drivers too). But Aiven Apps has no terminal, so this generator is
a service with a remote control API, the exact twin of the ingest service's
`POST /benchmarks`:

```bash
# fire a run (one at a time; a second POST gets 409 with the active run)
curl -s -X POST $LOADGEN/loadtests -H 'Content-Type: application/json' \
  -H "X-API-Key: $LOADGEN_API_KEY" \
  -d '{"mode":"firehose","rate":50000,"duration_s":60}'
# -> 202 {"id":"load-001-firehose","state":"RUNNING",...}

curl -s -H "X-API-Key: $LOADGEN_API_KEY" $LOADGEN/loadtests/load-001-firehose
```

## Modes

| Mode | Models | Parameters |
|---|---|---|
| `devices` | the mobile fleet: N virtual-thread devices, 1–5 events per upload, 2–6 s think time, honors 429 Retry-After | `users` (default 1000) |
| `firehose` | saturation probe: paced events/s as **single-event POSTs** (the "producers cannot batch" contract) | `rate` (default 10000), `batch_size` (default 1; >1 models pre-batched upstream services) |

Common: `duration_s` (default 60), `target_url` / `target_api_key` (default
from `TARGET_URL` / `TARGET_API_KEY` env).

## Results (`GET /loadtests/{id}`)

Live while running, frozen when done: `requests_sent`, `events_accepted`,
`events_rejected_429`, `request_errors`, achieved `events_per_sec`,
`request_latency_ms` (p50/p99, sampled), and — when the probe is enabled —
`e2e_latency_ms`: one marker event per second, polled in ClickHouse until
queryable, i.e. the full accepted → XADD → flusher → visible path.

Reading the numbers: achieved rate below target with 429s/errors = the
**target** is saturated (that's the finding); below target with zero 429s =
the **loadgen container** is undersized — scale it up before blaming the
ingest service. Pair every run with the ingest service's `GET /stats`
(stream length growing = flushers behind).

## Deploy next to the ingest service (Aiven Apps)

[compose.yaml](compose.yaml) is the recipe. Env:

- `TARGET_URL` — the ingest service's URL; `TARGET_API_KEY` — its X-API-Key
- `LOADGEN_API_KEY` — protects THIS service. **Always set it on a public
  deploy: an unauthenticated load generator is a DoS tool.**
- `CH_HOST`/`CH_PORT`/`CH_SSL`/`CH_DATABASE`/`CH_USER`/`CH_PASSWORD` —
  optional, enables the e2e probe (SELECT-only; `demo_ingest` works)

## Run locally

```bash
cd shared/loadgen-service
CH_HOST=localhost CH_PORT=8123 CH_PASSWORD=local mvn spring-boot:run
# defaults: target http://localhost:8080, port 8090
```

The k6 scripts in [../loadgen/](../loadgen/) remain the CLI-driven equivalent
for local work; this service exists for environments where you can't run k6
next to the target.
