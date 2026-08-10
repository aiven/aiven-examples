package io.aiven.ingest.valkey;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.aiven.ingest.sink.EventSink;
import io.aiven.ingest.tier.rest.EventDto;
import io.lettuce.core.api.StatefulRedisConnection;
import io.lettuce.core.api.sync.RedisCommands;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

import java.util.Map;
import java.util.concurrent.atomic.AtomicLong;

/**
 * The producer half of the Valkey buffer: POST /events -> XADD, one stream
 * entry per event (field "json" = the DTO as posted). Sub-millisecond against
 * an in-memory store, and the buffer is centralized - shared by all app
 * instances, surviving any of them.
 *
 * Backpressure: if ClickHouse is down or the flushers fall behind, nothing
 * gets acked and the stream grows until Valkey runs out of memory. Instead of
 * letting that happen we stop accepting (429) once XLEN passes
 * valkey.max-stream-length. XLEN is checked every CHECK_EVERY accepts, not per
 * event - one extra round trip per ~256 events.
 */
@Component
@ConditionalOnProperty(name = "ingest.buffer", havingValue = "valkey")
public class ValkeyEventSink implements EventSink {

    static final String FIELD_JSON = "json";
    private static final int CHECK_EVERY = 256;

    private final RedisCommands<String, String> commands;
    private final ObjectMapper mapper;
    private final String stream;
    private final long maxStreamLength;
    private final AtomicLong sinceCheck = new AtomicLong();
    private volatile long lastKnownLength;

    public ValkeyEventSink(StatefulRedisConnection<String, String> connection,
                           ObjectMapper mapper,
                           ValkeyProperties props) {
        this.commands = connection.sync();
        this.mapper = mapper;
        this.stream = props.stream();
        this.maxStreamLength = props.maxStreamLength();
    }

    @Override
    public boolean accept(EventDto event) {
        if (overCapacity()) {
            return false;
        }
        try {
            commands.xadd(stream, Map.of(FIELD_JSON, mapper.writeValueAsString(event)));
            return true;
        } catch (JsonProcessingException impossible) {
            // EventDto is a plain record of strings/numbers; treat as a bug.
            throw new IllegalStateException("Failed to serialize event", impossible);
        }
    }

    /**
     * Pipelined batch: dispatch every XADD asynchronously and wait once for
     * the last future (single-connection commands complete in order). One
     * POST of N events costs ~one round trip, not N - without this, a 200-
     * event upload serializes 200 round trips and the receiver saturates
     * long before the flusher does.
     */
    @Override
    public int acceptAll(java.util.List<EventDto> events) {
        if (events.isEmpty() || overCapacity()) {
            return 0;
        }
        var async = commands.getStatefulConnection().async();
        try {
            io.lettuce.core.RedisFuture<String> last = null;
            for (EventDto event : events) {
                last = async.xadd(stream, Map.of(FIELD_JSON, mapper.writeValueAsString(event)));
            }
            last.get(30, java.util.concurrent.TimeUnit.SECONDS);
            sinceCheck.addAndGet(events.size());
            return events.size();
        } catch (JsonProcessingException impossible) {
            throw new IllegalStateException("Failed to serialize event", impossible);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Interrupted while enqueueing batch", e);
        } catch (Exception e) {
            throw new IllegalStateException("Failed to enqueue batch to Valkey", e);
        }
    }

    @Override
    public long depth() {
        return commands.xlen(stream);
    }

    private boolean overCapacity() {
        if (sinceCheck.getAndIncrement() % CHECK_EVERY == 0) {
            lastKnownLength = commands.xlen(stream);
        }
        return lastKnownLength >= maxStreamLength;
    }
}
