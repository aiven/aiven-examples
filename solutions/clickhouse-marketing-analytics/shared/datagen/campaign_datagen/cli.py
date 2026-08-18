"""CLI: generate / upload / validate.

The horizon is anchored: "now = day 90" is horizon.anchor (or --anchor), the
batch generator writes days 1..89 behind it, and day 90 itself is streamed
live by livegen. generate is deterministic per (seed, anchor, day):
population/catalog/plan are built once over the full planning horizon with
rng([seed, 0]), then each day is generated with rng([seed, day_ordinal]).
Regenerating a subset of months (--only) warms up 3 days before the first
written day so cross-day email carryover (opens/clicks land up to 48h after
the send) is reproduced exactly. --through generates past the batch horizon
(up to plan_extra_days beyond the anchor) for demo-morning catch-up.
"""

from __future__ import annotations

import argparse
import time
from datetime import date, timedelta
from pathlib import Path

import numpy as np

from .catalog import build_catalog
from .config import load_config
from .engine import build_lookups, generate_day
from .plan import build_plan
from .population import build_population
from .writer import MonthWriter, write_root_manifest

WARM_UP_DAYS = 3


def horizon_dates(cfg, anchor_override: str | None = None) -> tuple[date, date, date, date]:
    """(start, batch_end, anchor, plan_end) for the anchored window.

    start..batch_end = days 1..89 (the batch backfill); anchor = day 90
    ("now", livegen's day); plan_end = anchor + plan_extra_days so livegen and
    --through catch-up stay inside the deterministic plan.
    """
    anchor = date.fromisoformat(anchor_override or cfg.horizon.anchor)
    start = anchor - timedelta(days=cfg.horizon.days - 1)
    batch_end = anchor - timedelta(days=1)
    plan_end = anchor + timedelta(days=getattr(cfg.horizon, "plan_extra_days", 0))
    return start, batch_end, anchor, plan_end


def _dates(start: date, end: date):
    d = start
    while d <= end:
        yield d
        d += timedelta(days=1)


def _out_root(cfg, args) -> Path:
    return Path(args.out or cfg.output.dir) / "campaign_events"


def cmd_generate(args) -> None:
    cfg = load_config(args.config)
    out_root = _out_root(cfg, args)

    start, batch_end, anchor, plan_end = horizon_dates(cfg, args.anchor)

    write_end = batch_end
    if args.through:
        write_end = date.fromisoformat(args.through)
        if not (start <= write_end <= plan_end):
            raise SystemExit(f"--through must be within {start}..{plan_end} "
                             f"(raise horizon.plan_extra_days to go further)")

    only = set(args.only.split(",")) if args.only else None
    write_days = [d for d in _dates(start, write_end)
                  if only is None or f"{d:%Y-%m}" in only]
    if not write_days:
        raise SystemExit(f"nothing to write: --only {args.only} outside {start}..{write_end}")

    # Scale the row target to the planning horizon so per-day density stays the
    # same whether or not the plan extends past the batch window. total_rows
    # covers the full 90-day window (batch days 1..89 + live day 90).
    window_days = cfg.horizon.days
    plan_days = (plan_end - start).days + 1
    target = int(cfg.targets.total_rows * plan_days / window_days)

    print(f"horizon {start}..{plan_end} (anchor/day-90 {anchor}, batch through {batch_end}), "
          f"writing {write_days[0]}..{write_days[-1]} ({len(write_days)} days), "
          f"seed {cfg.seed}")
    t0 = time.time()
    rng0 = np.random.default_rng([cfg.seed, 0])
    pop = build_population(cfg, rng0, start, plan_end)
    cat = build_catalog(cfg, rng0, start, plan_end)
    plan = build_plan(cfg, pop, cat, rng0, start, plan_end, target)
    lookups = build_lookups(cfg, cat, pop, rng0)
    print(f"built population ({pop.n:,} users), catalog ({cat.n} campaigns), "
          f"plan ({len(plan.day):,} planned events) in {time.time() - t0:.0f}s")

    sim_start = max(start, write_days[0] - timedelta(days=WARM_UP_DAYS))
    write_set = {d.toordinal() for d in write_days}
    writers: dict[str, MonthWriter] = {}
    carryover: dict = {}
    total = 0
    for d in _dates(sim_start, write_days[-1]):
        df = generate_day(cfg, pop, cat, plan, lookups, d.toordinal(), carryover, cfg.seed)
        if df is None:
            continue
        if d.toordinal() not in write_set:
            print(f"  {d} {len(df):>9,} rows (warm-up, not written)")
            continue
        mk = f"{d:%Y-%m}"
        if mk not in writers:
            writers[mk] = MonthWriter(out_root, mk, cfg.output.rows_per_file, cfg.output.compression)
        writers[mk].add(df)
        total += len(df)
        print(f"  {d} {len(df):>9,} rows (total {total:,}, {time.time() - t0:.0f}s)")

    manifests = [writers[mk].close() for mk in sorted(writers)]
    write_root_manifest(out_root, manifests)
    print(f"\ndone: {total:,} rows across {len(writers)} month(s) "
          f"in {time.time() - t0:.0f}s -> {out_root}")


def cmd_live(args) -> None:
    from .live import stream_live  # deferred: pulls redis only when streaming

    cfg = load_config(args.config)
    stream_live(cfg, args.anchor, rate=args.rate, valkey_url=args.valkey_url,
                stream=args.stream, pipeline_size=args.pipeline, days=args.days,
                max_stream_len=args.max_stream_len, dry_run=args.dry_run,
                loop=args.loop, rate_file=args.rate_file)


def cmd_upload(args) -> None:
    from .upload import upload  # deferred: needs google-cloud-storage + ADC

    cfg = load_config(args.config)
    bucket = args.bucket or cfg.gcs.bucket
    if not bucket:
        raise SystemExit("no bucket: set gcs.bucket in config or pass --bucket")
    months = args.only.split(",") if args.only else None
    upload(_out_root(cfg, args), bucket, cfg.gcs.prefix, months)


def cmd_validate(args) -> None:
    from .validate import validate

    cfg = load_config(args.config)
    validate(_out_root(cfg, args), cfg)


def main() -> None:
    p = argparse.ArgumentParser(prog="campaign-datagen",
                                description="Synthetic campaign_events backfill generator")
    p.add_argument("-c", "--config", default="config.yaml", help="config YAML (default: config.yaml)")
    p.add_argument("--out", help="override output.dir from the config")
    sub = p.add_subparsers(dest="cmd", required=True)

    g = sub.add_parser("generate", help="generate monthly Parquet parts + manifests")
    g.add_argument("--anchor", help="'now = day 90' date (YYYY-MM-DD); overrides horizon.anchor")
    g.add_argument("--only", help="comma-separated months to (re)generate, e.g. 2026-06,2026-07")
    g.add_argument("--through", help="generate through this date (YYYY-MM-DD), may extend "
                                     "past the batch window (day 89) for catch-up")
    g.set_defaults(fn=cmd_generate)

    lv = sub.add_parser("live", help="stream day 90 into Valkey Streams (the Post 1 pipeline) "
                                     "at a target rate")
    lv.add_argument("--anchor", help="'now = day 90' date (YYYY-MM-DD); overrides horizon.anchor")
    lv.add_argument("--rate", type=int, default=100_000, help="target events/s (default 100000)")
    lv.add_argument("--valkey-url", default="redis://localhost:6379/0",
                    help="Valkey URL (rediss://... for Aiven)")
    lv.add_argument("--stream", default="ingest:events", help="stream key (default ingest:events)")
    lv.add_argument("--pipeline", type=int, default=1000, help="XADDs per pipeline round trip")
    lv.add_argument("--days", type=int, default=1,
                    help="days to stream starting at the anchor (bounded by plan_extra_days)")
    lv.add_argument("--max-stream-len", type=int, default=1_000_000,
                    help="pause when XLEN exceeds this (0 disables)")
    lv.add_argument("--dry-run", action="store_true",
                    help="generate + pace without Valkey (measures achievable rate)")
    lv.add_argument("--loop", action="store_true",
                    help="build day 90 once and replay it forever (sustained load for "
                         "under-load benchmarks; replayed events land as new rows)")
    lv.add_argument("--rate-file",
                    help="poll this file for a new target rate at runtime (loop mode; "
                         "used by the bench rate sweep)")
    lv.set_defaults(fn=cmd_live)

    u = sub.add_parser("upload", help="upload generated months to GCS")
    u.add_argument("--bucket", help="GCS bucket (overrides gcs.bucket)")
    u.add_argument("--only", help="comma-separated months to upload")
    u.set_defaults(fn=cmd_upload)

    v = sub.add_parser("validate", help="check generated data against the validation gates")
    v.set_defaults(fn=cmd_validate)

    args = p.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
