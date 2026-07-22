# MQTT → Kafka → ClickHouse → Grafana on Aiven

End-to-end industrial IoT pipeline that replicates the kind of telemetry
Schaeffler's **OPTIME** condition-monitoring devices produce: wireless
vibration/temperature sensors mounted on rotating machinery (pumps,
motors, fans, gearboxes) publishing machine-health data over MQTT.

```
┌────────────────┐   MQTT    ┌───────────────┐   MQTT source   ┌──────────────┐
│ publisher      │ ────────> │ Mosquitto     │ ──────────────> │ Aiven for    │
│ (Aiven Apps)   │           │ (Aiven Apps)  │  Kafka Connect  │ Kafka        │
└────────────────┘           └───────────────┘                 └──────┬───────┘
                                                                      │ ClickHouse sink
                                                                      │ (Kafka Connect)
                             ┌───────────────┐                 ┌──────▼───────┐
                             │ Aiven for     │ <────────────── │ Aiven for    │
                             │ Grafana       │   dashboards    │ ClickHouse   │
                             └───────────────┘                 └──────────────┘
```

## The data

Each simulated machine carries an OPTIME-style sensor publishing every 5 s to
`optime/<site>/<machine_id>/telemetry`:

```json
{
  "device_id": "OPTIME-3A7F21",
  "machine_id": "PUMP-002",
  "machine_type": "centrifugal_pump",
  "site": "plant-herzogenaurach",
  "timestamp": "2026-07-22T09:15:04.211+00:00",
  "vibration_velocity_rms_mms": 2.412,
  "vibration_acceleration_rms_ms2": 1.108,
  "temperature_c": 47.35,
  "rpm": 1478,
  "iso_zone": "B",
  "condition": "acceptable",
  "battery_pct": 84.2,
  "rssi_dbm": -68
}
```

Vibration velocity RMS is classified against ISO 10816 zones (C = warning at
2.8 mm/s, D = alarm at 7.1 mm/s). Machines wear over time, trip into alarm,
and get "maintained" back to healthy, so dashboards always show a live mix
of good/warning/alarm states.

## 1. Deploy the MQTT broker (Aiven Apps)

[mqtt-broker/](mqtt-broker/) is a Mosquitto 2 image with password auth generated from
env vars at startup — nothing sensitive baked into the image, no bind
mounts needed.

Deploy via the [mqtt-broker/compose.yaml](mqtt-broker/compose.yaml) recipe with these
env vars set in the Aiven Apps configuration (see
[mqtt-broker/.env.example](mqtt-broker/.env.example)):

| Variable | Required | Default | Notes |
|----------|----------|---------|-------|
| `MQTT_USERNAME` | no | `iot` | Broker login user. |
| `MQTT_PASSWORD` | yes | — | Broker login password (set as a secret). |

Expose **port 9001** (the WebSockets listener). The Aiven Apps ingress is
HTTP(S)-only — it terminates TLS on 443 and forwards HTTP to the container,
so raw MQTT/TCP on 1883 does not pass through it; MQTT over WebSockets
does. External clients (the publisher and the Kafka Connect MQTT source)
connect with `wss://<app-hostname>:443`. Note the app's public hostname —
you'll need it below as `<BROKER_APP_HOSTNAME>`.

## 2. Deploy the publisher (Aiven Apps)

[publisher/](publisher/) is a continuous MQTT writer — a long-running
worker like `live-orders`: it simulates a configurable number of IoT
devices, publishes forever until SIGTERM, and serves `/healthz`
(liveness) and `/readyz` (ready once connected to the broker) on `PORT`
so Aiven Apps has a port to health-check.

Deploy via the [publisher/compose.yaml](publisher/compose.yaml) recipe with
these env vars (see [publisher/.env.example](publisher/.env.example)):

| Variable | Required | Default | Notes |
|----------|----------|---------|-------|
| `MQTT_HOST` | yes | — | `<BROKER_APP_HOSTNAME>` from step 1. |
| `MQTT_PASSWORD` | yes | — | Same as the broker (set as a secret). |
| `MQTT_PORT` | no | `1883` | `443` when the broker is on Aiven Apps. |
| `MQTT_USERNAME` | no | `iot` | |
| `MQTT_TLS` | no | `false` | `true` when the broker is on Aiven Apps. |
| `MQTT_TRANSPORT` | no | `tcp` | `websockets` when the broker is on Aiven Apps (HTTP-only ingress). |
| `MACHINE_COUNT` | no | `14` | Number of simulated IoT devices, cycled across 4 machine types. |
| `PUBLISH_INTERVAL_SECONDS` | no | `5` | Publish cadence per device. |
| `SITE` | no | `plant-herzogenaurach` | Run more instances with other sites for a multi-plant fleet. |
| `PORT` | no | `8080` | Health-server port: `/healthz`, `/readyz`. |

### Test locally first

```bash
MQTT_PASSWORD=changeme docker compose -f docker-compose.local.yml up --build
# in another terminal:
docker run --rm --network host eclipse-mosquitto:2 \
  mosquitto_sub -h localhost -u iot -P changeme -t 'optime/#' -v
```

## 3. MQTT source connector (Aiven for Kafka Connect)

Create the Kafka topic, then deploy
[kafka-connect/mqtt-source.json](kafka-connect/mqtt-source.json) after
replacing `<BROKER_APP_HOSTNAME>` and `<MQTT_PASSWORD>`. The connector
reaches the broker through the Aiven Apps HTTPS ingress, hence the
`wss://…:443` URL (Paho/Stream Reactor support MQTT over WebSockets;
raw `tcp://` only works to brokers with a directly reachable TCP port):

```bash
avn service topic-create $KAFKA_SERVICE iot_optime_telemetry --partitions 3 --replication 2

avn service connector create $KAFKA_CONNECT_SERVICE @kafka-connect/mqtt-source.json
avn service connector status $KAFKA_CONNECT_SERVICE mqtt-source-optime-telemetry
```

The connector is the Stream Reactor MQTT source. The KCQL subscribes to the
wildcard `optime/+/+/telemetry` and, together with `ByteArrayConverter`,
passes the JSON payload through byte-for-byte — so the Kafka topic contains
plain JSON that ClickHouse can read as `JSONEachRow`.

## 4. Sink the topic into Aiven for ClickHouse

The official ClickHouse sink connector writes the JSON messages from Kafka
straight into a MergeTree table — no Avro/Schema Registry required.

First create the target table by running
[clickhouse/setup.sql](clickhouse/setup.sql) against your ClickHouse service
(the table must exist before the connector starts). Then deploy
[kafka-connect/clickhouse-sink.json](kafka-connect/clickhouse-sink.json)
after filling in `<CLICKHOUSE_HOST>`, `<CLICKHOUSE_HTTPS_PORT>` and
`<CLICKHOUSE_PASSWORD>` (from the ClickHouse service's connection info):

```bash
avn service connector create $KAFKA_CONNECT_SERVICE @kafka-connect/clickhouse-sink.json
avn service connector status $KAFKA_CONNECT_SERVICE clickhouse-sink-optime-telemetry
```

Two settings in the sink config matter:

- `value.converter.schemas.enable=false` — the topic holds plain JSON (no
  schema envelope), passed through byte-for-byte by the MQTT source.
- `clickhouseSettings=date_time_input_format=best_effort` — lets ClickHouse
  parse the ISO-8601 `timestamp` values (with timezone offset) into
  `DateTime64(3)`.

Verify data is flowing:

```sql
SELECT machine_id, condition, max(timestamp) AS last_seen, count() AS rows
FROM iot.optime_telemetry GROUP BY machine_id, condition ORDER BY machine_id;
```

## 5. Grafana dashboard

1. Create the ClickHouse ↔ Grafana integration (or add a
   `grafana-clickhouse-datasource` datasource manually with the ClickHouse
   service's HTTPS host/port and credentials).
2. Import
   [grafana/dashboard-optime-condition-monitoring.json](grafana/dashboard-optime-condition-monitoring.json)
   and select the ClickHouse datasource when prompted.

The dashboard shows: machines in alarm/warning, fleet distribution across
ISO 10816 zones, vibration velocity with the 2.8 / 7.1 mm/s threshold lines,
acceleration, temperature, RPM, per-machine fleet status table, and sensor
battery levels.

## Layout

```
mqtt-broker/          Mosquitto broker (Dockerfile + compose.yaml for Aiven Apps)
publisher/            OPTIME-style fleet simulator, long-running worker (Dockerfile + compose.yaml)
kafka-connect/        MQTT source + ClickHouse sink connector configs
clickhouse/           Target table DDL (run before starting the sink)
grafana/              Importable dashboard JSON
docker-compose.local.yml   Broker + publisher together for local testing
```
