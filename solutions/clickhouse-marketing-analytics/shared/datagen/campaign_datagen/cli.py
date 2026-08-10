"""CLI: generate / upload / validate.

generate is deterministic per (seed, day): population/catalog/plan are built
once over the full planning horizon with rng([seed, 0]), then each day is
generated with rng([seed, day_ordinal]). Regenerating a subset of months
(--only) warms up 3 days before the first written day so cross-day email
carryover (opens/clicks land up to 48h after the send) is reproduced exactly.
--through generates month-to-date past the published horizon for the
demo-morning catch-up that replays through the Java ingest service.
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


def _parse_month(s: str) -> date:
    y, m = s.split("-")
    return date(int(y), int(m), 1)


def _add_months(d: date, k: int) -> date:
    y, m = d.year + (d.month - 1 + k) // 12, (d.month - 1 + k) % 12 + 1
    return date(y, m, 1)


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

    start = _parse_month(cfg.horizon.start_month)
    pub_end = _add_months(start, cfg.horizon.months) - timedelta(days=1)
    extra = getattr(cfg.horizon, "plan_extra_months", 0)
    plan_end = _add_months(start, cfg.horizon.months + extra) - timedelta(days=1)

    write_end = pub_end
    if args.through:
        write_end = date.fromisoformat(args.through)
        if not (start <= write_end <= plan_end):
            raise SystemExit(f"--through must be within {start}..{plan_end} "
                             f"(raise horizon.plan_extra_months to go further)")

    only = set(args.only.split(",")) if args.only else None
    write_days = [d for d in _dates(start, write_end)
                  if only is None or f"{d:%Y-%m}" in only]
    if not write_days:
        raise SystemExit(f"nothing to write: --only {args.only} outside {start}..{write_end}")

    # Scale the row target to the planning horizon so per-day density stays the
    # same whether or not the plan extends past the published months.
    pub_days = (pub_end - start).days + 1
    plan_days = (plan_end - start).days + 1
    target = int(cfg.targets.total_rows * plan_days / pub_days)

    print(f"horizon {start}..{plan_end} (published through {pub_end}), "
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
    g.add_argument("--only", help="comma-separated months to (re)generate, e.g. 2026-06,2026-07")
    g.add_argument("--through", help="generate month-to-date through this date (YYYY-MM-DD), "
                                     "may extend past the published horizon for catch-up")
    g.set_defaults(fn=cmd_generate)

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
