"""Remote-control wrapper around `campaign-datagen live` — livegen as a service.

Aiven Apps has no terminal, and livegen's only runtime control is the
--rate-file it polls. This wrapper closes that gap the same way
loadgen-service does for the ingest benchmarks: it runs livegen as a child
process (`live --loop --rate-file ...`) and exposes a small HTTP API so a
sweep harness (bench/rate_sweep.py --rate-url) can drive the rate from
anywhere:

  GET  /healthz    liveness, no auth (state only)
  GET  /status     child state, target rate, uptime, restarts, recent output
  POST /rate       {"rate": 30000} -> written to the rate file the child polls
  POST /start      spawn the child if stopped (rate file value applies)
  POST /stop       terminate the child (rate file is kept)

Auth mirrors loadgen-service: every route but /healthz requires
X-API-Key == LIVEGEN_API_KEY when the env var is set. **Always set it on a
public deploy — an unauthenticated load generator is a DoS tool.**

The child is supervised: an unexpected exit (Valkey blip, OOM) is restarted
after a backoff so a long sweep doesn't silently go quiet; /stop disables
the restart. Child stdout is mirrored to ours (Apps log stream) and kept in
a ring buffer for /status.

Stdlib only (http.server/subprocess/threading): the wrapper must not add
deps to the datagen image.
"""

from __future__ import annotations

import collections
import json
import os
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

RESTART_BACKOFF_S = 10
RING_LINES = 50


class LivegenSupervisor:
    def __init__(self, child_argv: list[str], rate_file: str, rate: int):
        self.child_argv = child_argv
        self.rate_file = rate_file
        self.started_at: float | None = None
        self.restarts = -1  # first start is not a restart
        self.desired_running = False
        self.proc: subprocess.Popen | None = None
        self.ring: collections.deque[str] = collections.deque(maxlen=RING_LINES)
        self.lock = threading.Lock()
        Path(rate_file).write_text(str(rate))

    # -- child lifecycle -------------------------------------------------
    def start(self) -> bool:
        with self.lock:
            if self.proc and self.proc.poll() is None:
                return False
            self.desired_running = True
            self._spawn()
            return True

    def stop(self) -> bool:
        with self.lock:
            self.desired_running = False
            if not (self.proc and self.proc.poll() is None):
                return False
            self.proc.terminate()
        try:
            self.proc.wait(timeout=15)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        return True

    def _spawn(self) -> None:
        self.restarts += 1
        self.started_at = time.time()
        self.proc = subprocess.Popen(
            self.child_argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1,
            env={**os.environ, "PYTHONUNBUFFERED": "1"})
        threading.Thread(target=self._pump, args=(self.proc,), daemon=True).start()

    def _pump(self, proc: subprocess.Popen) -> None:
        for line in proc.stdout:
            line = line.rstrip("\n")
            self.ring.append(line)
            print(f"[livegen] {line}", flush=True)
        proc.wait()
        self.ring.append(f"child exited rc={proc.returncode}")
        print(f"[livegen] child exited rc={proc.returncode}", flush=True)

    def watchdog(self) -> None:
        while True:
            time.sleep(RESTART_BACKOFF_S)
            with self.lock:
                dead = self.proc is not None and self.proc.poll() is not None
                if dead and self.desired_running:
                    print(f"[serve] child died (rc={self.proc.returncode}); "
                          f"restarting in-place", flush=True)
                    self._spawn()

    # -- state -----------------------------------------------------------
    def set_rate(self, rate: int) -> None:
        Path(self.rate_file).write_text(str(rate))

    def target_rate(self) -> int | None:
        try:
            return int(Path(self.rate_file).read_text().strip())
        except (OSError, ValueError):
            return None

    def status(self) -> dict:
        running = self.proc is not None and self.proc.poll() is None
        return {
            "state": "running" if running else "stopped",
            "target_rate": self.target_rate(),
            "rate_file": self.rate_file,
            "uptime_s": round(time.time() - self.started_at) if running else 0,
            "restarts": max(self.restarts, 0),
            "recent_output": list(self.ring)[-10:],
        }


def _make_handler(sup: LivegenSupervisor, api_key: str | None):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):  # route access logs to stdout
            print(f"[http] {self.address_string()} {fmt % args}", flush=True)

        def _send(self, code: int, payload: dict) -> None:
            body = json.dumps(payload).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _authed(self) -> bool:
            if not api_key:
                return True
            return self.headers.get("X-API-Key") == api_key

        def do_GET(self):
            if self.path == "/healthz":
                self._send(200, {"state": sup.status()["state"]})
            elif self.path == "/status":
                if not self._authed():
                    return self._send(401, {"error": "bad or missing X-API-Key"})
                self._send(200, sup.status())
            else:
                self._send(404, {"error": "unknown path"})

        def do_POST(self):
            if not self._authed():
                return self._send(401, {"error": "bad or missing X-API-Key"})
            if self.path == "/rate":
                length = int(self.headers.get("Content-Length") or 0)
                try:
                    rate = int(json.loads(self.rfile.read(length) or b"{}")["rate"])
                    if rate <= 0:
                        raise ValueError
                except (ValueError, KeyError, json.JSONDecodeError):
                    return self._send(400, {"error": 'body must be {"rate": <positive int>}'})
                sup.set_rate(rate)
                self._send(200, {"rate": rate, "state": sup.status()["state"]})
            elif self.path == "/start":
                started = sup.start()
                self._send(200 if started else 409, sup.status())
            elif self.path == "/stop":
                sup.stop()
                self._send(200, sup.status())
            else:
                self._send(404, {"error": "unknown path"})

    return Handler


def serve(args) -> None:
    api_key = os.environ.get("LIVEGEN_API_KEY") or args.api_key
    if not api_key:
        print("WARNING: no LIVEGEN_API_KEY set — the control API is "
              "unauthenticated. Never deploy this publicly.", flush=True)

    child_argv = [
        sys.executable, "-m", "campaign_datagen.cli", "-c", args.config,
        "live", "--loop", "--rate-file", args.rate_file,
        "--rate", str(args.rate), "--valkey-url", args.valkey_url,
        "--stream", args.stream, "--pipeline", str(args.pipeline),
        "--days", str(args.days), "--max-stream-len", str(args.max_stream_len),
    ]
    if args.anchor:
        child_argv += ["--anchor", args.anchor]

    sup = LivegenSupervisor(child_argv, args.rate_file, args.rate)
    # LIVEGEN_AUTOSTART=false: boot idle and wait for POST /start. The right
    # mode when a harness owns the lifecycle — the platform restarts
    # containers at will, and an auto-started generator poured 3M unwanted
    # rows into a freshly-loaded canonical table before anyone noticed.
    if os.environ.get("LIVEGEN_AUTOSTART", "true").lower() != "false":
        sup.start()
    else:
        print("[serve] LIVEGEN_AUTOSTART=false — idle until POST /start", flush=True)
    threading.Thread(target=sup.watchdog, daemon=True).start()

    server = ThreadingHTTPServer(("0.0.0.0", args.port), _make_handler(sup, api_key))
    print(f"[serve] livegen control API on :{args.port} "
          f"(auth {'ON' if api_key else 'OFF'})", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        sup.stop()
