"""Per-query reset for under-load benchmarks: return the table set to the
exact backfilled state while the live stream keeps running.

Correctness notes, learned the hard way at 679M rows:
  * Time predicates CANNOT separate live from backfill rows — the backfill
    legitimately contains rows timestamped past the anchor (email opens decay
    48h past day-89 sends). Separation is by PART LINEAGE only.
  * Row-count verification CANNOT work under a running stream — rows arrive
    between any listing and any count. Verification is by lineage too.

Mechanism — BLOCK NUMBERS, not part names and not part_log:
  * baseline = the max block number per table in the anchor-month partition,
    snapshotted while the tables are canonical and the stream is QUIESCED.
    Block numbers increase monotonically per partition, so a part whose
    min_block_number exceeds the snapshot came only from post-snapshot (live)
    inserts, no matter how many times it was merged — and there is no
    dependence on part_log flush timing (an earlier name/lineage-based
    version dropped freshly merged baseline parts because their part_log
    rows had not flushed yet; block ranges cannot have that race);
  * raw-table merges stay ON (merge pressure is part of the experiment); the
    partition is OPTIMIZEd into a few large settled parts beforehand, so the
    merge selector effectively never merges tiny live parts into them;
  * reset drops every part with min_block > baseline max; a part STRADDLING
    the boundary is a true baseline-live merge -> RAISES (repair: stop the
    stream, run restore_backfill.sh, which rebuilds the partition from the
    quiesced canonical backup);
  * merges ARE stopped on the five rollup tables (their merge cost is noise;
    it keeps reset cheap and exact there too).

The reset leaves at most ~a second of in-flight live rows — the stream is
running by design; "canonical at the start of each query" is the contract.
"""

from __future__ import annotations

import time

RAW = "campaign_events"
BACKUP = "campaign_events_anchor_month_backup"
ROLLUPS = ["daily_campaign_rollup", "keyword_rollup", "funnel_rollup",
           "landing_page_rollup", "email_health_rollup"]
RESET_PASSES = 2


class MixedMergeError(RuntimeError):
    """A background merge combined baseline and live parts — lineage can no
    longer separate them. Stop the stream and run restore_backfill.sh."""


def _parts(ch, table: str, partition: str) -> list[dict]:
    return ch.json(
        "SELECT name, min_block_number AS lo, max_block_number AS hi "
        "FROM system.parts WHERE active AND database = currentDatabase() "
        f"AND table = '{table}' AND partition_id = '{partition}'")["data"]


def ensure_backup(ch, partition: str) -> None:
    exists = ch.json("SELECT count() AS c FROM system.tables WHERE database = currentDatabase() "
                     f"AND name = '{BACKUP}'")["data"][0]["c"]
    if not int(exists):
        raise RuntimeError(
            f"{BACKUP} missing — create it while canonical AND quiesced "
            "(see /tmp/rebuild-aug.sh / restore_backfill.sh)")


def stop_rollup_merges(ch) -> None:
    for t in ROLLUPS:
        ch.raw(f"SYSTEM STOP MERGES {t}")


def start_merges(ch) -> None:
    for t in [RAW] + ROLLUPS:
        ch.raw(f"SYSTEM START MERGES {t}")


def snapshot(ch, partition: str) -> dict:
    """Record the max block number per table in the anchor-month partition.
    Block numbers are monotonically increasing per partition, so any part
    whose min_block_number exceeds this snapshot came ONLY from post-snapshot
    (live) inserts — regardless of how it was merged, and with no dependence
    on part_log flush timing."""
    base: dict = {"__partition__": partition}
    for t in [RAW] + ROLLUPS:
        parts = _parts(ch, t, partition)
        base[t] = max((int(p["hi"]) for p in parts), default=0)
    return base


def save(baseline: dict, path: str) -> None:
    import json
    json.dump(baseline, open(path, "w"))


def load(path: str) -> dict:
    import json
    return json.load(open(path))


def reset(ch, baseline: dict) -> None:
    part = baseline["__partition__"]
    for t in [RAW] + ROLLUPS:
        max_base = int(baseline[t])
        for _ in range(RESET_PASSES):
            todo = []
            for p in _parts(ch, t, part):
                lo, hi = int(p["lo"]), int(p["hi"])
                if hi <= max_base:
                    continue                       # baseline-descended: keep
                if lo > max_base:
                    todo.append(p["name"])         # purely live blocks: drop
                    continue
                raise MixedMergeError(
                    f"{t}: part {p['name']} spans blocks {lo}..{hi} across the "
                    f"baseline boundary {max_base} — stop livegen and run "
                    "restore_backfill.sh")
            if not todo:
                break
            for name in todo:
                try:
                    ch.raw(f"ALTER TABLE {t} DROP PART '{name}'")
                except Exception:
                    time.sleep(1)           # mid-merge or already gone; next pass catches it
