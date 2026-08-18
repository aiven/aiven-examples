#!/usr/bin/env bash
# Day-90 live tier: stream "today" into the Post 1 pipeline at ~100k events/s.
#
#   livegen ──pipelined XADD──▶ Valkey stream ──XREADGROUP──▶ in-app flusher
#                                                     └─▶ native bulk INSERT ▶ campaign_events
#                                                                    └─▶ MVs fire per batch ▶ rollups
#
# Prereqs: the Post 1 ingest service is running with its Valkey flusher
# (01-ingestion-benchmark/ingest-service, profile valkey), pointed at the same
# Valkey and ClickHouse as .env. Days 1..89 are already backfilled (make ingest).
#
# Usage: ./run_day90.sh [rate] [days]
#   rate  target events/s (default from LIVE_RATE or 100000)
#   days  days to stream from the anchor (default 1; bounded by plan_extra_days)
#
# Rate guidance, measured: on a local single-VM Docker setup (6 vCPU shared by
# ClickHouse + Valkey + flusher + queries) the end-to-end ceiling is
# ~55-60k events/s — ClickHouse saturates the cores, producer and Valkey have
# headroom. Set LIVE_RATE=60000 locally; the 100k/s target is for the Aiven
# deployment where the services don't share cores.
set -euo pipefail

RATE="${1:-${LIVE_RATE:-100000}}"
DAYS="${2:-1}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

# shellcheck disable=SC1091
[ -f "$ROOT/.env" ] && . "$ROOT/.env"

VALKEY_URL="${VALKEY_URL:-redis://localhost:6379/0}"
STREAM="${INGEST_STREAM:-ingest:events}"
CONFIG="${DATAGEN_CONFIG:-$ROOT/shared/datagen/config.yaml}"
ANCHOR_ARG=""
[ -n "${DATAGEN_ANCHOR:-}" ] && ANCHOR_ARG="--anchor $DATAGEN_ANCHOR"

cd "$ROOT/shared/datagen"
# shellcheck disable=SC2086
exec .venv/bin/campaign-datagen -c "$CONFIG" live \
    --rate "$RATE" --days "$DAYS" \
    --valkey-url "$VALKEY_URL" --stream "$STREAM" $ANCHOR_ARG
