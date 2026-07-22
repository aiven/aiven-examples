#!/usr/bin/env python3
"""Schaeffler OPTIME-style condition-monitoring data publisher.

Simulates a fleet of wireless vibration/temperature sensors mounted on
rotating machinery (pumps, motors, fans), the way Schaeffler OPTIME
devices monitor machine health. Each device publishes a JSON telemetry
message to an MQTT broker on a per-machine topic:

    optime/<site>/<machine_id>/telemetry

Metrics follow what OPTIME-class sensors actually measure:
  - vibration velocity RMS in mm/s (ISO 10816 machine-health indicator)
  - vibration acceleration RMS in m/s^2 (bearing-defect indicator)
  - surface temperature in Celsius
  - device health: battery %, radio RSSI

Machines drift through slow degradation cycles and occasionally trip
into warning/alarm zones so downstream dashboards have something to show.

Runs as a long-running worker: it publishes forever until SIGTERM/SIGINT
(how Aiven Apps stops a worker) and serves /healthz (liveness) and /readyz
(ready once connected to the broker) on PORT so the platform has a port
to probe. The fleet size is set with MACHINE_COUNT.
"""

import json
import logging
import math
import os
import random
import signal
import sys
import threading
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import paho.mqtt.client as mqtt

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("optime-publisher")

MQTT_HOST = os.environ.get("MQTT_HOST", "localhost")
MQTT_PORT = int(os.environ.get("MQTT_PORT", "1883"))
MQTT_USERNAME = os.environ.get("MQTT_USERNAME", "")
MQTT_PASSWORD = os.environ.get("MQTT_PASSWORD", "")
MQTT_TLS = os.environ.get("MQTT_TLS", "false").lower() == "true"
# "tcp" for raw MQTT, "websockets" when the broker sits behind an
# HTTP(S)-only ingress such as Aiven Apps (use with MQTT_TLS=true, port 443).
MQTT_TRANSPORT = os.environ.get("MQTT_TRANSPORT", "tcp")
PUBLISH_INTERVAL_SECONDS = float(os.environ.get("PUBLISH_INTERVAL_SECONDS", "5"))
MACHINE_COUNT = int(os.environ.get("MACHINE_COUNT", "14"))
SITE = os.environ.get("SITE", "plant-herzogenaurach")
TOPIC_PREFIX = os.environ.get("TOPIC_PREFIX", "optime")
PORT = int(os.environ.get("PORT", "8080"))

broker_connected = threading.Event()

# ISO 10816 zone boundaries (mm/s velocity RMS) for medium-size machines
# (class II). Zone A/B = good/acceptable, C = warning, D = alarm.
ISO_ZONE_C = 2.8
ISO_ZONE_D = 7.1


@dataclass
class Machine:
    machine_id: str
    machine_type: str
    device_id: str
    nominal_rpm: int
    base_velocity: float      # healthy vibration velocity RMS baseline, mm/s
    base_accel: float         # healthy acceleration RMS baseline, m/s^2
    base_temp: float          # healthy surface temperature baseline, C
    battery_pct: float = field(default_factory=lambda: random.uniform(60, 100))
    degradation: float = 0.0  # 0.0 healthy .. 1.0 fully degraded
    degradation_rate: float = field(default_factory=lambda: random.uniform(0.0001, 0.0008))
    phase: float = field(default_factory=lambda: random.uniform(0, 2 * math.pi))

    def tick(self) -> dict:
        """Advance the simulation one step and return a telemetry payload."""
        # Slow wear over time; a maintenance event resets it once in alarm.
        self.degradation = min(1.0, self.degradation + self.degradation_rate)
        if self.degradation >= 1.0 and random.random() < 0.05:
            log.info("maintenance performed on %s, resetting degradation", self.machine_id)
            self.degradation = 0.0

        # Battery drains slowly; swapped when empty.
        self.battery_pct = max(0.0, self.battery_pct - random.uniform(0.001, 0.004))
        if self.battery_pct <= 1.0:
            self.battery_pct = 100.0

        self.phase += random.uniform(0.05, 0.15)
        cyclic = math.sin(self.phase)  # process load cycles

        velocity = self.base_velocity * (1 + 0.15 * cyclic) + self.degradation * 8.0
        velocity += random.gauss(0, 0.1)
        velocity = max(0.1, velocity)

        accel = self.base_accel * (1 + 0.10 * cyclic) + self.degradation * 4.0
        accel += random.gauss(0, 0.05)
        accel = max(0.05, accel)

        temperature = self.base_temp + 4.0 * cyclic + self.degradation * 25.0
        temperature += random.gauss(0, 0.3)

        rpm = int(self.nominal_rpm * (1 + 0.02 * cyclic) + random.gauss(0, 5))

        if velocity >= ISO_ZONE_D:
            iso_zone, condition = "D", "alarm"
        elif velocity >= ISO_ZONE_C:
            iso_zone, condition = "C", "warning"
        elif velocity >= ISO_ZONE_C / 2:
            iso_zone, condition = "B", "acceptable"
        else:
            iso_zone, condition = "A", "good"

        return {
            "device_id": self.device_id,
            "machine_id": self.machine_id,
            "machine_type": self.machine_type,
            "site": SITE,
            "timestamp": datetime.now(timezone.utc).isoformat(timespec="milliseconds"),
            "vibration_velocity_rms_mms": round(velocity, 3),
            "vibration_acceleration_rms_ms2": round(accel, 3),
            "temperature_c": round(temperature, 2),
            "rpm": rpm,
            "iso_zone": iso_zone,
            "condition": condition,
            "battery_pct": round(self.battery_pct, 1),
            "rssi_dbm": random.randint(-85, -55),
        }


def build_fleet(count: int) -> list[Machine]:
    """Build `count` machines, cycling through the machine-type specs."""
    fleet_spec = [
        ("PUMP", "centrifugal_pump", 1480, 1.8, 0.9, 42.0),
        ("MOTOR", "electric_motor", 2960, 1.2, 0.6, 55.0),
        ("FAN", "axial_fan", 990, 2.2, 1.1, 38.0),
        ("GEARBOX", "gearbox", 740, 1.5, 1.4, 48.0),
    ]
    fleet = []
    for n in range(count):
        prefix, mtype, rpm, vel, acc, temp = fleet_spec[n % len(fleet_spec)]
        fleet.append(
            Machine(
                machine_id=f"{prefix}-{n // len(fleet_spec) + 1:03d}",
                machine_type=mtype,
                device_id=f"OPTIME-{random.randint(0, 0xFFFFFF):06X}",
                nominal_rpm=rpm,
                base_velocity=vel * random.uniform(0.9, 1.1),
                base_accel=acc * random.uniform(0.9, 1.1),
                base_temp=temp * random.uniform(0.95, 1.05),
                # stagger initial wear so the fleet is a mix of states
                degradation=random.uniform(0.0, 0.6),
            )
        )
    return fleet


class HealthHandler(BaseHTTPRequestHandler):
    """Liveness/readiness probes so Aiven Apps has a port to health-check."""

    def do_GET(self):  # noqa: N802 (http.server API)
        if self.path == "/healthz":
            status = 200
        elif self.path == "/readyz":
            status = 200 if broker_connected.is_set() else 503
        else:
            status = 404
        self.send_response(status)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(b"ok" if status == 200 else b"not ready")

    def log_message(self, *_):  # keep probe requests out of the logs
        pass


def start_health_server() -> ThreadingHTTPServer:
    server = ThreadingHTTPServer(("0.0.0.0", PORT), HealthHandler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    log.info("health server listening on :%d (/healthz, /readyz)", PORT)
    return server


def main() -> None:
    health_server = start_health_server()

    client = mqtt.Client(
        callback_api_version=mqtt.CallbackAPIVersion.VERSION2,
        client_id=f"optime-publisher-{SITE}",
        transport=MQTT_TRANSPORT,
    )
    if MQTT_USERNAME:
        client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)
    if MQTT_TLS:
        client.tls_set()

    def on_connect(c, u, f, rc, props=None):
        log.info("connected to %s:%s rc=%s", MQTT_HOST, MQTT_PORT, rc)
        broker_connected.set()

    def on_disconnect(c, u, f, rc, props=None):
        log.warning("disconnected rc=%s", rc)
        broker_connected.clear()

    client.on_connect = on_connect
    client.on_disconnect = on_disconnect

    # connect_async + reconnect loop: keep retrying if the broker isn't up
    # yet (or restarts) instead of crash-looping the whole worker.
    client.connect_async(MQTT_HOST, MQTT_PORT, keepalive=60)
    client.loop_start()

    running = True

    def stop(*_):
        nonlocal running
        running = False

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    fleet = build_fleet(MACHINE_COUNT)
    log.info("publishing telemetry for %d machines every %.1fs", len(fleet), PUBLISH_INTERVAL_SECONDS)

    while running:
        start = time.monotonic()
        if broker_connected.is_set():
            for machine in fleet:
                payload = machine.tick()
                topic = f"{TOPIC_PREFIX}/{SITE}/{machine.machine_id}/telemetry"
                client.publish(topic, json.dumps(payload), qos=1)
        else:
            log.warning("broker not connected, skipping publish cycle")
        elapsed = time.monotonic() - start
        time.sleep(max(0.0, PUBLISH_INTERVAL_SECONDS - elapsed))

    client.loop_stop()
    client.disconnect()
    health_server.shutdown()
    log.info("publisher stopped")


if __name__ == "__main__":
    sys.exit(main())
