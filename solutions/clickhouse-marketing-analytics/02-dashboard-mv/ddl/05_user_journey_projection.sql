-- Query optimization: the user_journey projection kept in the back
-- pocket ("Schema <-> query alignment" section). The base sort key
-- (channel, campaign_id, event_time, user_id) scatters each user's rows, so
-- the two journey queries (Q3 attribution, Q5 cohort) full-scan + hash-
-- aggregate. This projection stores ONLY the journey-query columns re-sorted
-- by (user_id, event_time): GROUP BY user_id then streams in order
-- (optimize_aggregation_in_order) instead of building a multi-GB hash table.
--
-- Deliberately added AFTER the ingestion benchmarks (the demo beat:
-- "schema work beats hardware"). Note: this ALTERs campaign_events, but the
-- table's columns/engine/sort key stay byte-identical; SHOW CREATE TABLE
-- gains a PROJECTION clause.
--
-- MATERIALIZE rewrites existing parts in the background -- watch progress in
-- system.mutations / system.merges. New inserts maintain it automatically
-- (its insert overhead is measured separately).

ALTER TABLE campaign_events ADD PROJECTION IF NOT EXISTS user_journey
(
    SELECT user_id, event_time, channel, campaign_id, event_type, conversion_value
    ORDER BY (user_id, event_time)
);

ALTER TABLE campaign_events MATERIALIZE PROJECTION user_journey;
