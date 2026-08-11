# observability — live metrics for the benchmark

Real-time view of a load test instead of curl-polling `/stats`:

```
ingest-service ──OTLP──┐
                       ├──> OTel Collector ──remote write──> Aiven for Metrics (Thanos) ──> Aiven for Grafana
loadgen-service ─OTLP──┘
```

Both apps carry Micrometer's OTLP registry and push every 15 s when enabled;
Aiven for Metrics ingests Prometheus remote write, so the OpenTelemetry
Collector is the translation hop (OTLP in, `prometheusremotewrite` out).
Thanos and Grafana are provisioned by [../infra/](../infra/) alongside the
data services, including the `datasource` integration that makes Thanos a
Grafana datasource automatically.

## What gets exported

| Metric | Source | Meaning |
|---|---|---|
| `ingest.rows` / `ingest.errors` (counters, tag `run`) | ingest-service | rows into ClickHouse / failed inserts — `run="valkey-flusher"` is the production path |
| `ingest.flush` (timer, bucketed) | ingest-service | bulk-insert round-trip latency |
| `valkey.stream.length` / `valkey.stream.pending` (gauges) | ingest-service | buffer backlog / delivered-not-acked |
| `loadgen.events.accepted` / `.rejected` / `loadgen.request.errors` (counters) | loadgen-service | offered load and backpressure |
| `loadgen.request` (timer, bucketed) | loadgen-service | POST /events latency as the producer sees it |
| `loadgen.e2e.latency` (summary, ms, bucketed) | loadgen-service | probe: event accepted → queryable in ClickHouse |

Plus Spring's built-ins (`http.server.requests`, JVM, CPU) from both apps.

## Setup

1. **Provision** (already in `infra/`): `terraform apply` creates the Thanos +
   Grafana services and their datasource integration.
2. **Deploy the collector** next to the apps —
   [otel-collector/compose.yaml](otel-collector/compose.yaml) is the Aiven
   Apps recipe. Env from terraform outputs:
   ```bash
   terraform output -raw thanos_remote_write_uri   # THANOS_REMOTE_WRITE_URI
   terraform output -raw thanos_user               # THANOS_USER
   terraform output -raw thanos_password           # THANOS_PASSWORD
   ```
   (If the URI embeds `user:password@`, strip it — credentials go through the
   collector's basicauth extension.)
3. **Point the apps at it**: set on both ingest-service and loadgen-service:
   ```
   OTLP_METRICS_ENABLED=true
   OTEL_EXPORTER_OTLP_ENDPOINT=http://<collector-host>:4318
   ```
4. **Dashboard**: log into Grafana (`terraform output grafana_url` /
   `grafana_user` / `grafana_password`), import
   [grafana/ingestion-benchmark-dashboard.json](grafana/ingestion-benchmark-dashboard.json),
   pick the provisioned Thanos datasource.

Local variant: `docker compose --profile observability up -d` at the repo
folder root starts the collector next to ClickHouse/Valkey (still needs the
`THANOS_*` env — the metrics land in the real Aiven Thanos), then run the apps
with the two `OTLP_*` variables.

## Reading the dashboard during a run

- **accepted/s vs rows/s**: the two ends of the pipe. Diverging while
  **stream length** grows = flushers behind producers (scale
  `VALKEY_FLUSHERS` or instances).
- **pending > 0** in steady state = a consumer died; entries are waiting out
  `claim-min-idle-ms` before `XAUTOCLAIM` rescues them.
- **e2e latency** should sit near `flush_interval + insert time`; watch it
  respond live to a `PUT /config` retune.
- **rejected (429)/s** = backpressure engaged — the sink's
  `max-stream-length` bound is doing its job.

Note on metric names in Grafana: the remote-write conversion appends unit
suffixes (`ingest_rows_total`, `ingest_flush_milliseconds_bucket`,
`loadgen_e2e_latency_milliseconds_bucket`, ...). The dashboard JSON assumes
those (verified against a live push); if a panel is empty, check the actual name in Grafana's metric browser
under the `ingest_`/`loadgen_`/`valkey_` prefixes.
