-- Persistent storage for the OPTIME telemetry stream.
--
-- The ClickHouse sink connector (kafka-connect/clickhouse-sink.json) writes
-- directly into this table, so it MUST exist before the connector starts.
-- The connector maps topic iot_optime_telemetry -> iot.optime_telemetry via
-- its topic2TableMap setting, and its date_time_input_format=best_effort
-- setting lets the ISO-8601 timestamps parse into DateTime64.

CREATE DATABASE IF NOT EXISTS iot;

CREATE TABLE IF NOT EXISTS iot.optime_telemetry
(
    device_id                       String,
    machine_id                      String,
    machine_type                    LowCardinality(String),
    site                            LowCardinality(String),
    timestamp                       DateTime64(3),
    vibration_velocity_rms_mms      Float64,
    vibration_acceleration_rms_ms2  Float64,
    temperature_c                   Float64,
    rpm                             Int32,
    iso_zone                        LowCardinality(String),
    condition                       LowCardinality(String),
    battery_pct                     Float32,
    rssi_dbm                        Int16
)
ENGINE = ReplicatedMergeTree
PARTITION BY toYYYYMM(timestamp)
ORDER BY (site, machine_id, timestamp)
TTL toDateTime(timestamp) + INTERVAL 90 DAY;
