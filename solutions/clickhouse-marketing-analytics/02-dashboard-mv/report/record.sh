#!/usr/bin/env bash
# One-shot recording of the report page assembling itself.
# Starts server.py, records the reveal with Playwright, stops the server.
#   ./record.sh [optimized|naive] [port]
set -euo pipefail
TRACK="${1:-optimized}"
PORT="${2:-8088}"
HERE="$(cd "$(dirname "$0")" && pwd)"

python3 "$HERE/server.py" "$PORT" & SRV=$!
trap 'kill $SRV 2>/dev/null || true' EXIT
sleep 1

if ! npx --yes playwright --version >/dev/null 2>&1; then
  echo "playwright not installed: npm i playwright && npx playwright install chromium" >&2
  exit 1
fi
node "$HERE/record.mjs" "http://localhost:$PORT/?track=$TRACK" "$HERE/recordings/$TRACK"
