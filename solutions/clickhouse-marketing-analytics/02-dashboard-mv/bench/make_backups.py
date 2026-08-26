#!/usr/bin/env python3
"""Create the canonical anchor-month backup tables — the restore source for
every under-load reset (live_reset.restore_from_backup / _rebuild_rollup).

MUST run while the tables are canonical and the stream is quiesced; refuses
otherwise. Rebuilds all six backups from the CURRENT table state:

  campaign_events_anchor_month_backup           (raw, no projection)
  <rollup>_anchor_month_backup                  (the five rollups)

  CANONICAL_ROWS=<manifest total> python3 make_backups.py [partition]
"""

import os
import sys

import live_reset
from bench_lib import ClickHouse

partition = sys.argv[1] if len(sys.argv) > 1 else "202608"
EXPECTED = int(os.environ.get("CANONICAL_ROWS", 679_357_898))

ch = ClickHouse()
got = int(ch.json("SELECT count() AS c FROM campaign_events", timeout=120)["data"][0]["c"])
if got != EXPECTED:
    raise SystemExit(f"refusing to snapshot backups: campaign_events has {got} rows, "
                     f"canonical is {EXPECTED} — restore/reload first")

for t in [live_reset.RAW] + live_reset.ROLLUPS:
    backup = f"{t}_anchor_month_backup"
    print(f"{backup}: ", end="", flush=True)
    ch.raw(f"DROP TABLE IF EXISTS {backup}")
    ch.raw(f"CREATE TABLE {backup} AS {t}")
    if t == live_reset.RAW:
        ch.raw(f"ALTER TABLE {backup} DROP PROJECTION IF EXISTS user_journey")
    ch.raw(f"INSERT INTO {backup} SELECT * FROM {t} WHERE _partition_id = '{partition}'",
           query_id=f"mkbackup-{t}",
           settings={"max_execution_time": 3600, "max_insert_threads": 4},
           timeout=3600)
    n = ch.json(f"SELECT count() AS c FROM {backup}", timeout=120)["data"][0]["c"]
    print(f"{int(n):,} rows", flush=True)
print("backups ready")
