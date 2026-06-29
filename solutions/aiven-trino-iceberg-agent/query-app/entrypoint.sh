#!/usr/bin/env bash
#
# query-app entrypoint: start Trino, wait until it's ready, then run the MCP server.
#
# mcp-trino probes its Trino connection once at startup and exits on failure, so
# Trino must be accepting requests before we launch it. We start Trino in the
# background, poll its /v1/info until it reports started, then `exec` the MCP
# server so it becomes the container's foreground process (its exit stops the
# container, which is the signal Aiven Apps watches).
set -euo pipefail

TRINO_PORT="${TRINO_PORT:-8080}"
MCP_PORT="${MCP_PORT:-9097}"
TRINO_READY_URL="http://localhost:${TRINO_PORT}/v1/info"
TRINO_WAIT_SECONDS="${TRINO_WAIT_SECONDS:-120}"

echo "==> starting Trino"
/usr/lib/trino/bin/run-trino &
TRINO_PID=$!

echo "==> waiting up to ${TRINO_WAIT_SECONDS}s for Trino at ${TRINO_READY_URL}"
deadline=$(( $(date +%s) + TRINO_WAIT_SECONDS ))
# /v1/info reports {"starting":false,...} once the server is ready to serve queries.
until curl -fsS "$TRINO_READY_URL" 2>/dev/null | grep -q '"starting":false'; do
  if ! kill -0 "$TRINO_PID" 2>/dev/null; then
    echo "FATAL: Trino exited before becoming ready" >&2
    wait "$TRINO_PID" || true
    exit 1
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "FATAL: Trino not ready after ${TRINO_WAIT_SECONDS}s" >&2
    exit 1
  fi
  sleep 2
done
echo "==> Trino is ready"

echo "==> starting Trino MCP server on :${MCP_PORT} (/mcp)"
exec /usr/local/bin/trino-mcp
