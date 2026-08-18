#!/bin/sh
# Applies the shared schema into campaign_analytics on first container start.
# Needed because the image's initdb hook runs *.sql against the default database,
# ignoring CLICKHOUSE_DB - so we run the files ourselves with --database set.
# Only the raw table (+ diagnostics) here: the Post 2 rollups/MVs/projection
# (02-dashboard-mv/ddl/) are an explicit optimization step (make optimize),
# not part of the baseline environment.
set -e
for f in /ddl/01_campaign_events.sql; do
    [ -f "$f" ] || continue
    echo "applying $f to campaign_analytics"
    clickhouse-client --multiquery --host 127.0.0.1 \
        -u "$CLICKHOUSE_USER" --password "$CLICKHOUSE_PASSWORD" \
        --database campaign_analytics < "$f"
done
