#!/usr/bin/env python3
"""Read-latency vs ingest-rate sweep — "how fast can the stream run before
the dashboard feels it?" (the read-side twin of Post 1's sender sweep).

Requires livegen running in loop mode, either colocated with --rate-file:
  campaign-datagen live --rate <start> --loop --rate-file /tmp/livegen-rate
or remote behind its control API (campaign-datagen serve, e.g. on Aiven
Apps), driven with --rate-url + LIVEGEN_API_KEY env:
  LIVEGEN_API_KEY=... python3 rate_sweep.py --rate-url https://<livegen-app>

Per rate rung: write the target to the rate file, hold WARMUP_S for steady
state, measure the ACHIEVED insert rate from the raw table's row count, then
run every optimized query RUNS times
and record medians. Output: results/rate_sweep.csv plus a per-rung verdict
against the idle baselines: "unchanged" (<= 1.2x idle median — noise band)
and "acceptable" (<= 1.5x).

  python3 rate_sweep.py --rates 5000..60000..5000 --idle results/optimized_idle.csv
"""

from __future__ import annotations

import argparse
import csv
import statistics
import time
from pathlib import Path

from bench_lib import ClickHouse

HERE = Path(__file__).parent
QUERIES = HERE.parent / "queries" / "optimized"
SWEEP_QUERIES = ["q1", "q2", "q3", "q4", "q5", "q6", "q7", "q8"]  # full suite; q5 costs ~5min/rung
WARMUP_S = 60
RUNS = 3
UNCHANGED, ACCEPTABLE = 1.2, 1.5


def parse_rates(spec: str) -> list[int]:
    if ".." in spec:
        parts = [int(x) for x in spec.split("..")]
        start, stop = parts[0], parts[1]
        step = parts[2] if len(parts) > 2 else 10_000
        return list(range(start, stop + 1, step))
    return [int(x) for x in spec.split(",")]


def row_count(ch: ClickHouse) -> int:
    return int(ch.json("SELECT count() AS c FROM campaign_events")["data"][0]["c"])


def set_rate(args, rate: int) -> None:
    """Point the generator at a new target: POST to the livegen control API
    (campaign-datagen serve) when --rate-url is given, else the local rate
    file a colocated `live --loop --rate-file` polls."""
    if not args.rate_url:
        Path(args.rate_file).write_text(str(rate))
        return
    import json
    import os
    import urllib.request
    req = urllib.request.Request(
        f"{args.rate_url.rstrip('/')}/rate",
        data=json.dumps({"rate": rate}).encode(),
        headers={"Content-Type": "application/json",
                 "X-API-Key": os.environ.get("LIVEGEN_API_KEY", "")},
        method="POST")
    with urllib.request.urlopen(req, timeout=30) as resp:
        body = json.load(resp)
    if body.get("state") != "running":
        raise SystemExit(f"livegen is not running behind {args.rate_url} "
                         f"(state={body.get('state')!r}) — POST /start it first")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--rates", default="5000..60000..5000")
    p.add_argument("--rate-file", default="/tmp/livegen-rate")
    p.add_argument("--rate-url",
                   help="livegen control API base URL (campaign-datagen serve), e.g. "
                        "https://livegen.example.aiven.app — rate changes go to POST "
                        "/rate instead of --rate-file; auth via LIVEGEN_API_KEY env")
    p.add_argument("--idle", default=str(HERE / "results" / "optimized_idle.csv"),
                   help="idle baseline CSV for the verdicts")
    p.add_argument("--out", default=str(HERE / "results" / "rate_sweep.csv"))
    p.add_argument("--baseline-file", default="/tmp/live_baseline.json",
                   help="canonical part baseline (write it QUIESCED with "
                        "snapshot_baseline.py); live rows are reset before EVERY query")
    p.add_argument("--stop-when-degraded", action="store_true",
                   help="end the sweep at the first rung whose worst query exceeds "
                        f"{ACCEPTABLE}x idle — the answer is the last 'unchanged' rung")
    args = p.parse_args()

    idle = {}
    try:
        for r in csv.DictReader(open(args.idle)):
            idle[r["query"].split("_")[0]] = float(r["median_s"])
    except OSError:
        print(f"warning: no idle baseline at {args.idle}; verdicts skipped")

    ch = ClickHouse()
    import live_reset
    baseline = live_reset.load(args.baseline_file)
    live_reset.ensure_backup(ch, baseline["__partition__"])
    live_reset.stop_rollup_merges(ch)

    sql = {q: next(QUERIES.glob(f"{q}_*.sql")).read_text() for q in SWEEP_QUERIES}
    rows_out = []
    try:
        for rate in parse_rates(args.rates):
            set_rate(args, rate)
            live_reset.reset(ch, baseline)
            print(f"\n=== target {rate:,}/s: warmup {WARMUP_S}s ===", flush=True)
            time.sleep(WARMUP_S / 2)
            c0, t0 = row_count(ch), time.time()
            time.sleep(WARMUP_S / 2)
            achieved = int((row_count(ch) - c0) / (time.time() - t0))
            rec = {"target_rate": rate, "achieved_rate": achieved}
            worst = 0.0
            for q in SWEEP_QUERIES:
                live_reset.reset(ch, baseline)   # every query starts canonical
                walls = sorted(ch.run_measured(sql[q], tag=f"sweep-{rate}-{q}")["wall_s"]
                               for _ in range(RUNS))
                med = statistics.median(walls)
                rec[q] = round(med, 3)
                if q in idle and idle[q] > 0.05:  # sub-50ms queries are all noise
                    worst = max(worst, med / idle[q])
            rec["worst_vs_idle"] = round(worst, 2)
            rec["verdict"] = ("unchanged" if worst <= UNCHANGED else
                              "acceptable" if worst <= ACCEPTABLE else "degraded")
            rows_out.append(rec)
            print(f"    achieved {achieved:,}/s | " +
                  " ".join(f"{q}={rec[q]}s" for q in SWEEP_QUERIES) +
                  f" | worst {rec['worst_vs_idle']}x -> {rec['verdict']}", flush=True)
            if args.stop_when_degraded and rec["verdict"] == "degraded":
                print("    degraded — stopping the sweep here", flush=True)
                break
    finally:
        live_reset.reset(ch, baseline)
        live_reset.start_merges(ch)

    with open(args.out, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=rows_out[0].keys())
        w.writeheader()
        w.writerows(rows_out)
    print(f"\nwrote {args.out}")


if __name__ == "__main__":
    main()
