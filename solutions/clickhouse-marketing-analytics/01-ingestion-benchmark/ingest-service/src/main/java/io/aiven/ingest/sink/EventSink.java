package io.aiven.ingest.sink;

import io.aiven.ingest.tier.rest.EventDto;

/**
 * Where POST /events puts a single event. Two implementations:
 *
 * - memory (default): the in-memory EventBuffer - fast, but the buffer
 *   dies with the app. This is the ladder's rung, kept for the benchmark.
 * - valkey: Valkey Streams - the production architecture used after the
 *   ladder. XADD per event into a centralized stream shared by all app
 *   instances; an in-app flusher consumes it via a consumer group and bulk
 *   inserts through the winning native-client path. Select with
 *   ingest.buffer=valkey.
 */
public interface EventSink {

    /** Enqueue one event. false = backpressure: the caller should return 429. */
    boolean accept(EventDto event);

    /** Current buffer depth (queue size / stream length) for 429 responses. */
    long depth();
}
