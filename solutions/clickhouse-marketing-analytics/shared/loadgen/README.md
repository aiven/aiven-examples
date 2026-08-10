# Load test — the buffered REST API (the mobile fleet)

k6 scenario simulating a 100k-device mobile fleet against `POST /events`
(the buffered REST ingestion tier). Two traffic shapes:

| Scenario | Shape | Why |
|---|---|---|
| `steady` (default) | ramp to 2,000 devices, 1–5 event batch every 2–6s ≈ 1–2.5k events/s for 3 min | assumed steady state for 100k users at typical mobile instrumentation (~1 event per 20–100s of active use) |
| `burst` | steady baseline, then spike to 20,000 devices in 20s, hold 1 min | a full-base push notification — the MoEngage case that motivated the whole project |

## Run

```bash
# start the service in REST mode (no --tier): local CH or Aiven profile
JAVA_HOME=/opt/homebrew/opt/openjdk@25 mvn -f ingest-service spring-boot:run

k6 run shared/loadgen/k6-events.js                       # steady
k6 run -e SCENARIO=burst shared/loadgen/k6-events.js     # push blast
k6 run -e BASE_URL=http://<vm>:8080 shared/loadgen/k6-events.js
```

## What to watch

- `events_accepted` / `events_rejected` counters: steady state should show zero
  429s; the burst may trigger them — that is the bounded-queue backpressure
  working, not a failure. Devices honor `Retry-After` and resend.
- `http_req_duration p(99) < 500ms` threshold: the API itself must never be the
  bottleneck; it only enqueues.
- End-to-end freshness while the test runs:
  `SELECT now() - max(event_time) FROM campaign_events` — must stay under ~2s
  (the flush interval bounds it).
- `system.parts` active count: batched flushes keep it flat even at burst rates.
