#!/usr/bin/env python3
"""Snapshot the canonical part baseline for live_reset. MUST run while the
tables are canonical and the stream is quiesced (no livegen, backlog drained).

  python3 snapshot_baseline.py [partition] [out.json]
"""

import sys

import live_reset
from bench_lib import ClickHouse

partition = sys.argv[1] if len(sys.argv) > 1 else "202608"
out = sys.argv[2] if len(sys.argv) > 2 else "/tmp/live_baseline.json"

EXPECTED = 679_357_898

ch = ClickHouse()
got = int(ch.json("SELECT count() AS c FROM campaign_events")["data"][0]["c"])
if got != EXPECTED:
    raise SystemExit(f"refusing to snapshot: campaign_events has {got} rows, "
                     f"canonical is {EXPECTED} — restore first (restore_backfill.sh)")
live_reset.ensure_backup(ch, partition)
# Settle every table's anchor-month partition BEFORE freezing rollup merges:
# a just-rebuilt partition holds one small part per MV insert block, and a
# fragmented baseline stays fragmented forever once merges stop — measured as
# a false 5x "degradation" of the rollup reads at a trivial 5k/s.
for t in [live_reset.RAW] + live_reset.ROLLUPS:
    live_reset._merges(ch, "START", t)
    ch.raw(f"OPTIMIZE TABLE {t} PARTITION {partition}", timeout=1800)
live_reset.stop_rollup_merges(ch)
base = live_reset.snapshot(ch, partition)
live_reset.save(base, out)
print(f"baseline saved to {out}: " +
      ", ".join(f"{t}={len(v)} parts" for t, v in base.items() if isinstance(v, set)))
