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
        f"AND table = '{table}' AND partition_id = '{partition}'",
        timeout=120)["data"]


def ensure_backup(ch, partition: str) -> None:
    exists = ch.json("SELECT count() AS c FROM system.tables WHERE database = currentDatabase() "
                     f"AND name = '{BACKUP}'")["data"][0]["c"]
    if not int(exists):
        raise RuntimeError(
            f"{BACKUP} missing — create it while canonical AND quiesced "
            "(see /tmp/rebuild-aug.sh / restore_backfill.sh)")


def _merges(ch, verb: str, table: str) -> None:
    """SYSTEM {STOP,START} MERGES, tolerated on managed ClickHouse: Aiven
    locks SYSTEM MERGES behind PROTECTED ACCESS MANAGEMENT, so there the
    rollups keep merging and reset() self-heals a mixed merge from the
    per-rollup anchor-month backup instead (see reset)."""
    try:
        ch.raw(f"SYSTEM {verb} MERGES {table}")
    except Exception as e:
        if "ACCESS_DENIED" not in str(getattr(e, "read", lambda: b"")() or e) and \
           "Not enough privileges" not in str(e):
            raise
        print(f"    (SYSTEM {verb} MERGES {table} not permitted here — managed "
              f"ClickHouse; relying on self-healing reset)", flush=True)


def stop_rollup_merges(ch) -> None:
    for t in ROLLUPS:
        _merges(ch, "STOP", t)


def start_merges(ch) -> None:
    for t in [RAW] + ROLLUPS:
        _merges(ch, "START", t)


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


def _rebuild_rollup(ch, t: str, partition: str, baseline: dict) -> None:
    """Self-heal a baseline-live merge on a ROLLUP: rebuild its anchor-month
    partition from the per-rollup backup and re-snapshot its block boundary.
    Needed on managed ClickHouse where rollup merges cannot be stopped.
    Live MV rows inserted concurrently with the rebuild may slip under the
    new boundary — bounded by seconds of stream, noise at rollup scale."""
    backup = f"{t}_anchor_month_backup"
    exists = ch.json("SELECT count() AS c FROM system.tables WHERE database = "
                     f"currentDatabase() AND name = '{backup}'")["data"][0]["c"]
    if not int(exists):
        raise MixedMergeError(
            f"{t}: baseline-live merge and no {backup} to self-heal from — "
            "stop livegen and run restore_backfill.sh")
    print(f"    ({t}: baseline-live merge; rebuilding partition {partition} "
          f"from {backup})", flush=True)
    # Idempotent under network flakes: the INSERT is pinned to a query_id
    # (disables blind transport retries, which could double-insert); on a
    # flake the partition is dropped again and the insert restarted fresh.
    import uuid
    for attempt in range(2):
        try:
            ch.raw(f"ALTER TABLE {t} DROP PARTITION {partition}", timeout=300)
            ch.raw(f"INSERT INTO {t} SELECT * FROM {backup}",
                   query_id=f"rebuild-{t}-{uuid.uuid4().hex[:8]}",
                   settings={"max_execution_time": 1800}, timeout=1800)
            break
        except Exception:
            if attempt == 1:
                raise
            time.sleep(5)
    baseline[t] = max((int(p["hi"]) for p in _parts(ch, t, partition)), default=0)


def restore_from_backup(ch, partition: str) -> None:
    """Rebuild the anchor-month partition everywhere from the canonical raw
    backup (MVs re-fire and rebuild the rollups). The managed-ClickHouse
    reset: per-part DROP PART fights the merge scheduler on a replicated
    cluster (drops block behind merges of the very parts being dropped —
    measured 120s+ per part under a live stream), so under-load protocols
    restore per RUNG with this instead of resetting per query."""
    ensure_backup(ch, partition)
    for t in [RAW] + ROLLUPS:
        ch.raw(f"ALTER TABLE {t} DROP PARTITION {partition}", timeout=300)
    ch.raw(f"INSERT INTO {RAW} SELECT * FROM {BACKUP}",
           query_id=f"restore-{int(time.time())}",
           settings={"max_execution_time": 3600, "max_insert_threads": 4,
                     "async_insert": 0},
           timeout=3600)


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
                if t != RAW:
                    _rebuild_rollup(ch, t, part, baseline)
                    max_base = int(baseline[t])
                    todo = None                    # boundary moved: restart the pass
                    break
                raise MixedMergeError(
                    f"{t}: part {p['name']} spans blocks {lo}..{hi} across the "
                    f"baseline boundary {max_base} — stop livegen and run "
                    "restore_backfill.sh")
            if todo is None:
                continue
            if not todo:
                break
            for name in todo:
                try:
                    ch.raw(f"ALTER TABLE {t} DROP PART '{name}'", timeout=120)
                except Exception:
                    time.sleep(1)           # mid-merge or already gone; next pass catches it
