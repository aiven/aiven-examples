#!/usr/bin/env python3
"""The bench harness as a service — run the Post 2 benchmarks from inside the
target's region instead of a laptop.

Two laptop-shaped failures motivated this: the sweep dies when the lid
closes (livegen then streams junk unattended), and a multi-hour run makes
hundreds of sequential WAN calls, where one dropped connection hangs the
whole thing. Deployed next to ClickHouse (Aiven Apps), both vanish — and
measured wall times stop including laptop-to-Frankfurt RTT.

API (X-API-Key = BENCH_API_KEY on everything but /healthz):

  GET  /healthz            liveness (no auth)
  GET  /status             active/last job: state, args, uptime, recent output
  POST /jobs               start a job; 409 while one is active. Body:
    {"kind": "verify"}     equality gate, all 8 pairs (q5 via spill)
    {"kind": "backup", "partition": "202608"}    canonical backup tables
    {"kind": "baseline", "partition": "202608"}
    {"kind": "idle", "track": "optimized", "label": "idle_sweep", "runs": 5}
    {"kind": "sweep", "rates": "5000..60000..5000", "reset_mode": "per-rung",
     "stop_when_degraded": true, "idle": "results/optimized_idle_sweep.csv"}
    {"kind": "campaign"}   backup -> baseline -> idle -> sweep, unattended
  Set CANONICAL_ROWS when the dataset's manifest total isn't the default.
  POST /stop               terminate the active job (livegen stopped too)
  GET  /results            list files under results/
  GET  /results/<name>     raw file (CSV / job log)

A sweep job owns livegen's lifecycle through its control API (LIVEGEN_URL):
started and awaited before rate_sweep launches, ALWAYS stopped when the job
ends — success, failure, or /stop — so a dead driver can never leave the
generator pouring rows unattended (measured cost of that: 109M junk rows in
one night).

Env: CH_URL / CH_USER / CH_PASSWORD / CH_DATABASE (bench_lib), LIVEGEN_URL,
LIVEGEN_API_KEY, BENCH_API_KEY, BENCH_PORT (default 8100).

Stdlib only, same as the rest of bench/.
"""

from __future__ import annotations

import collections
import json
import os
import re
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).parent
RESULTS = HERE / "results"
RING_LINES = 200
BASELINE_FILE = "/tmp/live_baseline.json"


def _steps(kind: str, body: dict) -> list[list[str]]:
    py = sys.executable
    partition = str(body.get("partition", "202608"))
    verify = [py, "-u", "verify_equality.py",
              "q1", "q2", "q3", "q4", "q6", "q7", "q8"]  # q5 gate needs spill:
    verify_q5 = [py, "-u", "verify_q5_spill.py"]
    backup = [py, "-u", "make_backups.py", partition]
    baseline = [py, "-u", "snapshot_baseline.py", partition, BASELINE_FILE]
    idle = [py, "-u", "run_suite.py",
            "--track", str(body.get("track", "optimized")),
            "--label", str(body.get("label", "idle_sweep")),
            "--runs", str(body.get("runs", 5)),
            "--skip", str(body.get("skip", ""))]
    sweep = [py, "-u", "rate_sweep.py",
             "--rates", str(body.get("rates", "5000..60000..5000")),
             "--rate-url", os.environ["LIVEGEN_URL"],
             "--idle", str(body.get("idle", "results/optimized_idle_sweep.csv")),
             "--reset-mode", str(body.get("reset_mode", "per-rung")),
             "--partition", partition,
             "--baseline-file", BASELINE_FILE,
             "--out", str(body.get("out", "results/rate_sweep_aiven.csv"))] + \
            (["--stop-when-degraded"] if body.get("stop_when_degraded", True) else [])
    return {"verify": [verify, verify_q5],
            "backup": [backup],
            "baseline": [baseline],
            "idle": [idle],
            "sweep": [sweep],
            # backup before baseline: snapshot_baseline's ensure_backup gate
            "campaign": [backup, baseline, idle, sweep]}[kind]


def _needs_livegen(argv: list[str]) -> bool:
    return "rate_sweep.py" in argv[1:2] or any("rate_sweep.py" in a for a in argv)


class Livegen:
    def __init__(self):
        self.url = os.environ.get("LIVEGEN_URL", "").rstrip("/")
        self.key = os.environ.get("LIVEGEN_API_KEY", "")

    def _call(self, path: str, method: str = "POST") -> dict:
        req = urllib.request.Request(f"{self.url}{path}", method=method,
                                     headers={"X-API-Key": self.key})
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.load(resp)

    def start_and_wait(self, log, timeout_s: int = 600) -> None:
        self._call("/start")
        log("livegen: starting (plan build takes minutes)")
        t0 = time.time()
        while time.time() - t0 < timeout_s:
            st = self._call("/status", method="GET")
            if any("sent," in line for line in st.get("recent_output", [])):
                log("livegen: streaming")
                return
            time.sleep(10)
        raise RuntimeError(f"livegen not streaming after {timeout_s}s")

    def stop(self, log) -> None:
        try:
            self._call("/stop")
            log("livegen: stopped")
        except Exception as e:  # never mask the job's own outcome
            log(f"livegen: stop FAILED ({e}) — check it manually!")


class JobRunner:
    def __init__(self):
        self.lock = threading.Lock()
        self.proc: subprocess.Popen | None = None
        self.job: dict | None = None
        self.ring: collections.deque[str] = collections.deque(maxlen=RING_LINES)
        self.stop_requested = False
        self.livegen = Livegen()

    def log(self, line: str) -> None:
        self.ring.append(line)
        if self.job:
            with open(RESULTS / f"job-{self.job['id']}.log", "a") as f:
                f.write(line + "\n")
        print(line, flush=True)

    def start(self, kind: str, body: dict) -> dict:
        with self.lock:
            if self.job and self.job["state"] == "running":
                return {}
            self.job = {"id": f"{kind}-{uuid.uuid4().hex[:8]}", "kind": kind,
                        "args": body, "state": "running",
                        "started": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                        "t0": time.time(), "exit_code": None}
            self.ring.clear()
            self.stop_requested = False
        threading.Thread(target=self._run, args=(_steps(kind, body),), daemon=True).start()
        return self.job

    def _run(self, steps: list[list[str]]) -> None:
        state, code = "done", 0
        for argv in steps:
            if self.stop_requested:
                state = "stopped"
                break
            uses_livegen = _needs_livegen(argv)
            try:
                if uses_livegen:
                    self.livegen.start_and_wait(self.log)
                self.log(f"step: {' '.join(argv[1:])}")
                self.proc = subprocess.Popen(
                    argv, cwd=HERE, stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT, text=True, bufsize=1)
                for line in self.proc.stdout:
                    self.log(line.rstrip("\n"))
                code = self.proc.wait()
                if code != 0:
                    state = "stopped" if self.stop_requested else "failed"
                    break
            except Exception as e:
                self.log(f"step error: {e}")
                state, code = "failed", -1
                break
            finally:
                if uses_livegen:
                    self.livegen.stop(self.log)
        self.job.update(state=state, exit_code=code)
        self.log(f"job {self.job['id']}: {state}")

    def stop(self) -> bool:
        self.stop_requested = True
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            return True
        return False

    def status(self) -> dict:
        if not self.job:
            return {"state": "no job yet"}
        out = {k: v for k, v in self.job.items() if k != "t0"}
        if self.job["state"] == "running":
            out["uptime_s"] = round(time.time() - self.job["t0"])
        out["recent_output"] = list(self.ring)[-15:]
        return out


def _make_handler(runner: JobRunner, api_key: str | None):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            print(f"[http] {self.address_string()} {fmt % args}", flush=True)

        def _send(self, code: int, payload, raw: bytes | None = None) -> None:
            body = raw if raw is not None else json.dumps(payload).encode()
            self.send_response(code)
            self.send_header("Content-Type",
                             "text/plain" if raw is not None else "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _authed(self) -> bool:
            return not api_key or self.headers.get("X-API-Key") == api_key

        def do_GET(self):
            if self.path == "/healthz":
                return self._send(200, {"state": runner.status().get("state")})
            if not self._authed():
                return self._send(401, {"error": "bad or missing X-API-Key"})
            if self.path == "/status":
                self._send(200, runner.status())
            elif self.path == "/results":
                files = sorted(p.name for p in RESULTS.iterdir() if p.is_file())
                self._send(200, {"files": files})
            elif self.path.startswith("/results/"):
                name = self.path[len("/results/"):]
                if not re.fullmatch(r"[\w.\-]+", name) or not (RESULTS / name).is_file():
                    return self._send(404, {"error": "no such result"})
                self._send(200, None, raw=(RESULTS / name).read_bytes())
            else:
                self._send(404, {"error": "unknown path"})

        def do_POST(self):
            if not self._authed():
                return self._send(401, {"error": "bad or missing X-API-Key"})
            if self.path == "/jobs":
                length = int(self.headers.get("Content-Length") or 0)
                try:
                    body = json.loads(self.rfile.read(length) or b"{}")
                    kind = body.pop("kind")
                    _steps(kind, body)  # validates kind and arg shapes
                except (KeyError, json.JSONDecodeError):
                    return self._send(400, {"error": 'body needs {"kind": "verify"|'
                                            '"backup"|"baseline"|"idle"|"sweep"|"campaign", ...}'})
                job = runner.start(kind, body)
                if not job:
                    return self._send(409, runner.status())
                self._send(202, runner.status())
            elif self.path == "/stop":
                runner.stop()
                self._send(200, runner.status())
            else:
                self._send(404, {"error": "unknown path"})

    return Handler


def main() -> None:
    api_key = os.environ.get("BENCH_API_KEY")
    if not api_key:
        print("WARNING: no BENCH_API_KEY — this API can DROP DATA PARTS. "
              "Never deploy it publicly unauthenticated.", flush=True)
    if not os.environ.get("LIVEGEN_URL"):
        print("WARNING: LIVEGEN_URL unset — sweep jobs will fail at start", flush=True)
    RESULTS.mkdir(exist_ok=True)
    runner = JobRunner()
    port = int(os.environ.get("BENCH_PORT", "8100"))
    server = ThreadingHTTPServer(("0.0.0.0", port), _make_handler(runner, api_key))
    print(f"[bench-server] control API on :{port} "
          f"(auth {'ON' if api_key else 'OFF'})", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
