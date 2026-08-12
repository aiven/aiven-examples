#!/bin/bash
# Run ingest-service and loadgen-service side by side in one container.
# Loadgen's default target becomes localhost - override TARGET_URL only to
# deliberately measure the through-ingress path again.
#
# Each JVM gets a fixed fraction of container RAM (the default 25%-each would
# waste half); ingest gets the larger share, it holds the hot path.
# bash, not sh: the JRE image has no curl/wget, so the readiness probe is a
# bash /dev/tcp connect, and the exit watcher needs bash's `wait -n`.
set -eu

: "${TARGET_URL:=http://localhost:8080}"
export TARGET_URL

# Ports are pinned as args, NOT via SERVER_PORT: both JVMs see the same
# environment in a shared container, so an env port would collide.
java -XX:MaxRAMPercentage=45 -jar /app/ingest.jar --server.port=8080 &
INGEST_PID=$!

# Loadgen only starts once ingest's port accepts connections, so a
# crash-looping ingest fails the whole container instead of leaving a
# half-alive pair.
for i in $(seq 1 60); do
  if (exec 3<>/dev/tcp/localhost/8080) 2>/dev/null; then
    exec 3>&- 3<&-
    break
  fi
  if ! kill -0 "$INGEST_PID" 2>/dev/null; then
    echo "ingest-service exited during startup" >&2
    exit 1
  fi
  if [ "$i" -eq 60 ]; then
    echo "ingest-service did not open :8080 in 120s" >&2
    kill "$INGEST_PID" 2>/dev/null || true
    exit 1
  fi
  sleep 2
done

java -XX:MaxRAMPercentage=25 -jar /app/loadgen.jar --server.port=8090 &
LOADGEN_PID=$!

# SIGTERM (Apps stop/redeploy): stop loadgen first so no new events arrive,
# then ingest, which drains its buffer in Spring graceful shutdown.
term() {
  kill "$LOADGEN_PID" 2>/dev/null || true
  wait "$LOADGEN_PID" 2>/dev/null || true
  kill "$INGEST_PID" 2>/dev/null || true
  wait "$INGEST_PID" 2>/dev/null || true
  exit 0
}
trap term TERM INT

# If either JVM dies, take the container down so the platform restarts it.
wait -n || true
echo "a service exited; stopping container" >&2
term
