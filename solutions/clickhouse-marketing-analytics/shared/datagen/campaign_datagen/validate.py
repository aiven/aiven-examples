"""Quick distribution checks against the validation gates.

Reads the generated Parquet lazily and prints: event mix vs target, rows/day,
funnel stage counts, first-vs-last-touch channel divergence, null ratios and
email list-health — the tune-before-dashboards checklist.
"""

from __future__ import annotations

from pathlib import Path

import polars as pl


def validate(root: Path, cfg) -> None:
    lf = pl.scan_parquet(str(root / "month=*" / "part-*.parquet"))

    total = lf.select(pl.len()).collect().item()
    days = lf.select((pl.col("event_time").max() - pl.col("event_time").min()).dt.total_days() + 1).collect().item()
    print(f"rows: {total:,}  ({total / max(days, 1):,.0f}/day over {days} days)")

    print("\nevent mix (actual vs target):")
    mix = lf.group_by("event_type").len().sort("len", descending=True).collect()
    targets = vars(cfg.targets.event_mix)
    for et, n in mix.iter_rows():
        print(f"  {et:<12} {n / total:6.2%}  (target {targets.get(et, 0):.2%})")

    print("\nfunnel (distinct users):")
    funnel = (lf.filter(pl.col("event_type").is_in(["page_view", "lead", "trial_start", "purchase"]))
              .group_by("event_type").agg(pl.col("user_id").n_unique().alias("users")).collect())
    fd = dict(funnel.iter_rows())
    for et in ("page_view", "lead", "trial_start", "purchase"):
        print(f"  {et:<12} {fd.get(et, 0):>12,}")

    print("\nattribution: last-touch (purchase) vs first-touch-proxy (journey pv) channel share:")
    last = (lf.filter(pl.col("event_type") == "purchase").group_by("channel").len().collect())
    first = (lf.filter(pl.col("session_id").str.starts_with("s1-") & (pl.col("event_type") == "page_view"))
             .group_by("channel").len().collect())
    lt, ft = dict(last.iter_rows()), dict(first.iter_rows())
    l_sum, f_sum = sum(lt.values()) or 1, sum(ft.values()) or 1
    max_div = 0.0
    for ch in sorted(set(lt) | set(ft)):
        ls, fs = lt.get(ch, 0) / l_sum, ft.get(ch, 0) / f_sum
        rel = abs(ls - fs) / max(fs, 1e-9)
        max_div = max(max_div, rel)
        print(f"  {ch:<12} last {ls:6.2%}  first {fs:6.2%}  (rel diff {rel:.0%})")
    print(f"  -> max relative divergence {max_div:.0%} (gate: >= 15%)")

    print("\nnulls: ", end="")
    nulls = lf.select(
        (pl.col("keyword").null_count() / pl.len()).alias("keyword"),
        (pl.col("conversion_value").null_count() / pl.len()).alias("conversion_value"),
    ).collect()
    print(f"keyword {nulls['keyword'][0]:.1%} null, conversion_value {nulls['conversion_value'][0]:.1%} null")

    print("\nemail list-health (campaigns crossing alert thresholds):")
    email = (lf.filter(pl.col("channel") == "email")
             .group_by("campaign_id")
             .agg(sends=(pl.col("event_type") == "email_send").sum(),
                  unsubs=(pl.col("event_type") == "unsubscribe").sum(),
                  bounces=(pl.col("event_type") == "bounce").sum())
             .filter(pl.col("sends") > 1000)
             .with_columns(unsub_rate=pl.col("unsubs") / pl.col("sends"),
                           bounce_rate=pl.col("bounces") / pl.col("sends"))
             .collect())
    alerts = email.filter((pl.col("unsub_rate") > 0.005) | (pl.col("bounce_rate") > 0.02))
    print(f"  {len(alerts)} of {len(email)} email campaigns alerting "
          f"(target: only the {cfg.catalog.bad_email_segments} bad segments)")
    for row in alerts.sort("bounce_rate", descending=True).head(10).iter_rows(named=True):
        print(f"  {row['campaign_id']:<40} unsub {row['unsub_rate']:.2%}  bounce {row['bounce_rate']:.2%}")
