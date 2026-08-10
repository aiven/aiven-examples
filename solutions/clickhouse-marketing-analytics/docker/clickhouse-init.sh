#!/bin/sh
# Applies the repo's shared/schema/ files into campaign_analytics on first container start.
# Needed because the image's initdb hook runs *.sql against the default database,
# ignoring CLICKHOUSE_DB - so we run the files ourselves with --database set.
set -e
for f in /ddl/01_campaign_events.sql /ddl/02_daily_campaign_rollup.sql; do
    echo "applying $f to campaign_analytics"
    clickhouse-client --multiquery --host 127.0.0.1 \
        -u "$CLICKHOUSE_USER" --password "$CLICKHOUSE_PASSWORD" \
        --database campaign_analytics < "$f"
done
