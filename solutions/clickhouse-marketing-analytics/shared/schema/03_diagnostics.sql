-- Diagnostics to run live during tier 1 (and while walking the ladder).
-- These are SELECTs, not schema — keep this file open in a query console.

-- Active parts for campaign_events: watch this explode under row-by-row inserts
-- and stay flat under batched inserts.
SELECT count() AS active_parts
FROM system.parts
WHERE table = 'campaign_events' AND active;

-- Part creation rate + sizes (recent parts, newest first).
SELECT name, rows, formatReadableSize(bytes_on_disk) AS size, modification_time
FROM system.parts
WHERE table = 'campaign_events' AND active
ORDER BY modification_time DESC
LIMIT 20;

-- Is async_insert actually buffering? (Tier 1 verification — must show entries
-- while inserting with async_insert=1.)
SELECT * FROM system.asynchronous_inserts;

-- Async insert outcomes / errors (flush log; requires async_insert_log enabled,
-- which it is by default on recent ClickHouse).
SELECT event_time, query, bytes, status, exception
FROM system.asynchronous_insert_log
ORDER BY event_time DESC
LIMIT 20;

-- Merge pressure: currently running merges.
SELECT database, table, elapsed, progress, num_parts, result_part_name
FROM system.merges;

-- Rejections / delays under part pressure.
SELECT event, value
FROM system.events
WHERE event IN ('DelayedInserts', 'RejectedInserts', 'TooManyPartsExceptions');

-- Freshness probe for the demo (<1-2s end-to-end latency claim).
SELECT now() - max(event_time) AS ingest_lag_seconds, count() AS total_rows
FROM campaign_events;
