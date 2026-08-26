# bench-runner: the Post 2 benchmark harness behind an HTTP job API
# (bench/bench_server.py), deployed in the same region as ClickHouse so
# benchmark runs survive laptop lids and skip the WAN entirely.
#
# Build context: the solution root (see compose.yaml).
FROM python:3.12-slim

# The harness is stdlib-only; it needs the bench scripts AND the query
# files they measure (../queries relative to bench/).
WORKDIR /app
COPY 02-dashboard-mv/queries /app/02-dashboard-mv/queries
COPY 02-dashboard-mv/bench/*.py /app/02-dashboard-mv/bench/

WORKDIR /app/02-dashboard-mv/bench
CMD ["python3", "-u", "bench_server.py"]
