#!/usr/bin/env bash
# Restore the canonical backfill state after a live experiment.
#
# DO NOT restore by deleting event_time >= anchor: the backfill legitimately
# contains rows timestamped past the anchor (email opens/clicks decay up to
# 48h after day-89 sends), so a time predicate removes canonical rows —
# measured: 9,603 rows lost at 679M. Live rows are only separable by PART
# lineage, which is what bench/live_reset.py does during experiments.
#
# This script is the between-experiments restore: drop the anchor-month
# partition everywhere and re-insert it from the one-time canonical backup
# (campaign_events_anchor_month_backup, created by live_reset.ensure_backup
# while the table was canonical). The MVs re-fire and rebuild the rollups'
# anchor-month partitions.
#
#   ./restore_backfill.sh [partition YYYYMM] [expected_rows]
set -euo pipefail

# Mutual exclusion: two concurrent restores interleave their DROP/INSERT and
# corrupt the partition (measured: ~1.9 August copies). One at a time.
LOCK=/tmp/restore_backfill.lock
exec 9>"$LOCK"
if ! flock -n 9; then echo "another restore is already running ($LOCK)" >&2; exit 1; fi

PARTITION="${1:-202608}"
EXPECTED="${2:-679357898}"
BACKUP=campaign_events_anchor_month_backup
cc() { docker exec clickhouse-marketing-analytics-clickhouse-1 clickhouse-client \
        --password "${CH_PASSWORD:-local}" --database "${CH_DATABASE:-campaign_analytics}" -q "$1"; }

if pgrep -f 'campaign-datagen live' >/dev/null; then
  echo "livegen is still streaming — stop it first" >&2; exit 1
fi
HAVE=$(cc "SELECT count() FROM system.tables WHERE database = currentDatabase() AND name = '$BACKUP'")
[ "$HAVE" = "1" ] || { echo "no $BACKUP — cannot restore (create it while canonical via live_reset.ensure_backup)" >&2; exit 1; }

echo "dropping partition $PARTITION everywhere and re-inserting from $BACKUP ..."
for t in campaign_events daily_campaign_rollup keyword_rollup funnel_rollup landing_page_rollup email_health_rollup; do
  cc "ALTER TABLE $t DROP PARTITION $PARTITION"
done
cc "INSERT INTO campaign_events SELECT * FROM $BACKUP SETTINGS async_insert = 0, max_execution_time = 1800"

GOT=$(cc "SELECT count() FROM campaign_events" | tr -d '[:space:]')
ROLLUP=$(cc "SELECT sum(events) FROM daily_campaign_rollup" | tr -d '[:space:]')
echo "raw rows:         $GOT (expected $EXPECTED)"
echo "Q1 rollup events: $ROLLUP"
if [ "$GOT" = "$EXPECTED" ] && [ "$ROLLUP" = "$EXPECTED" ]; then
  echo "RESTORE OK"
else
  echo "RESTORE MISMATCH" >&2; exit 1
fi
