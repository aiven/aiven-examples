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

    /**
     * Enqueue a producer batch; returns how many were accepted (stops at the
     * first rejection). Sinks with per-event round trips should override this
     * to pipeline - one POST of N events must not cost N round trips.
     */
    default int acceptAll(java.util.List<EventDto> events) {
        int accepted = 0;
        for (EventDto e : events) {
            if (!accept(e)) break;
            accepted++;
        }
        return accepted;
    }

    /**
     * Enqueue a producer batch given as RAW JSON element bytes, returning how
     * many were accepted. The hot path: the servlet slices the request body
     * without ever decoding it to chars or binding objects, and sinks that
     * store JSON verbatim (valkey) write those bytes straight to the wire.
     * The default parses each element and delegates to acceptAll().
     */
    default int acceptAllRaw(java.util.List<byte[]> rawEvents,
                             com.fasterxml.jackson.databind.ObjectMapper mapper) {
        java.util.List<EventDto> events = new java.util.ArrayList<>(rawEvents.size());
        try {
            for (byte[] raw : rawEvents) {
                events.add(mapper.readValue(raw, EventDto.class));
            }
        } catch (java.io.IOException e) {
            throw new IllegalArgumentException("malformed event JSON: " + e.getMessage());
        }
        return acceptAll(events);
    }

    /** Current buffer depth (queue size / stream length) for 429 responses. */
    long depth();
}
