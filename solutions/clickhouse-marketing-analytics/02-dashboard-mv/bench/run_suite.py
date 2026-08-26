#!/usr/bin/env python3
"""Benchmark the query suite: {naive, optimized} x {idle, load}.

Runs every query in ../queries/<track>/ N times (median of 5 by default),
captures wall time plus system.query_log metrics via bench_lib, and writes
results/<track>_<label>.csv + results/versions.csv. The article quotes these
CSVs and nothing else.

  python3 run_suite.py --track both --label idle
  python3 run_suite.py --track both --label load     # with run_day90.sh running

Env: CH_URL / CH_USER / CH_PASSWORD / CH_DATABASE (see bench_lib).
"""

from __future__ import annotations

import argparse
import csv
import statistics
import sys
from datetime import datetime, timezone
from pathlib import Path

from bench_lib import ClickHouse

HERE = Path(__file__).parent
QUERIES = HERE.parent / "queries"


def run_track(ch: ClickHouse, track: str, label: str, runs: int, out_dir: Path,
              baseline: dict | None = None, skip: set[str] | None = None) -> None:
    files = sorted((QUERIES / track).glob("q*.sql"))
    if skip:
        # e.g. naive q5 cannot execute on business-16 (MEMORY_LIMIT_EXCEEDED
        # at the ~10 GiB cap) — that DNF is recorded prose, not a median.
        files = [f for f in files if f.stem.split("_")[0] not in skip]
    if not files:
        sys.exit(f"no queries under {QUERIES / track}")
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"{track}_{label}.csv"
    rows = []
    for f in files:
        sql = f.read_text()
        name = f.stem
        if baseline is not None:
            import live_reset
            live_reset.reset(ch, baseline)  # each query starts from the canonical backfill
        print(f"[{track}/{label}] {name}: ", end="", flush=True)
        samples = []
        for i in range(runs):
            m = ch.run_measured(sql, tag=f"{track}-{name}-{label}")
            samples.append(m)
            print(f"{m['wall_s']:.2f}s ", end="", flush=True)
        walls = sorted(s["wall_s"] for s in samples)
        median = statistics.median(walls)
        # metrics from the sample closest to the median wall time
        rep = min(samples, key=lambda s: abs(s["wall_s"] - median))
        rows.append({
            "query": name, "track": track, "label": label, "runs": runs,
            "median_s": round(median, 3),
            "min_s": round(walls[0], 3), "max_s": round(walls[-1], 3),
            "server_ms": rep["server_ms"], "read_rows": rep["read_rows"],
            "read_bytes": rep["read_bytes"], "memory_usage": rep["memory_usage"],
            "result_rows": rep["result_rows"],
        })
        print(f"-> median {median:.2f}s, read_rows {rep['read_rows']}")
    with open(out, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=rows[0].keys())
        w.writeheader()
        w.writerows(rows)
    print(f"wrote {out}")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--track", choices=["naive", "optimized", "both"], default="both")
    p.add_argument("--label", default="idle", help="idle | load (tag for the run conditions)")
    p.add_argument("--runs", type=int, default=5)
    p.add_argument("--out", default=str(HERE / "results"))
    p.add_argument("--baseline-file", default=None,
                   help="under-load mode: reset live rows before each query using this "
                        "baseline JSON (write it QUIESCED with snapshot_baseline.py)")
    p.add_argument("--skip", default="",
                   help="comma-separated query prefixes to leave out, e.g. 'q5' for "
                        "the naive track on memory-capped managed plans")
    args = p.parse_args()

    ch = ClickHouse()
    baseline = None
    if args.baseline_file:
        import live_reset
        baseline = live_reset.load(args.baseline_file)
        live_reset.ensure_backup(ch, baseline["__partition__"])
        live_reset.stop_rollup_merges(ch)
    ver = ch.version()
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    with open(out_dir / "versions.csv", "a", newline="") as fh:
        csv.writer(fh).writerow([datetime.now(timezone.utc).isoformat(), ch.url, ver, args.label])
    print(f"ClickHouse {ver} at {ch.url}")

    tracks = ["naive", "optimized"] if args.track == "both" else [args.track]
    try:
        skip = {s.strip() for s in args.skip.split(",") if s.strip()}
        for t in tracks:
            run_track(ch, t, args.label, args.runs, out_dir, baseline, skip)
    finally:
        if baseline is not None:
            import live_reset
            live_reset.reset(ch, baseline)   # leave the tables canonical
            live_reset.start_merges(ch)


if __name__ == "__main__":
    main()
