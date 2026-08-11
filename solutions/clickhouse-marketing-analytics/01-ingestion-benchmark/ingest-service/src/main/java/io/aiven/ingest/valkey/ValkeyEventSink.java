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

    private static final org.slf4j.Logger log =
            org.slf4j.LoggerFactory.getLogger(ValkeyEventSink.class);
    static final String FIELD_JSON = "json";
    private static final int CHECK_EVERY = 256;

    private final RedisCommands<String, String> commands;
    private final ObjectMapper mapper;
    private final String stream;
    private final long maxStreamLength;
    private final boolean asyncAck;
    private final io.micrometer.core.instrument.Counter asyncFailures;
    private final AtomicLong sinceCheck = new AtomicLong();
    private volatile long lastKnownLength;

    // Kafka-producer-style accumulator (ingest.valkey-send=batched): handlers
    // append and return; one sender thread drains up to send-batch events or
    // send-linger-ms and ships them as ONE pipelined flush on a dedicated
    // connection - one socket write for N events instead of N event-loop
    // wakeups. Implies fire-and-forget semantics for the linger window.
    private final boolean batchedSend;
    private final int sendBatch;
    private final long sendLingerMs;
    private final java.util.concurrent.ArrayBlockingQueue<String> accumulator;
    private final StatefulRedisConnection<String, String> senderConnection;

    public ValkeyEventSink(StatefulRedisConnection<String, String> connection,
                           io.lettuce.core.RedisClient client,
                           ObjectMapper mapper,
                           ValkeyProperties props,
                           io.micrometer.core.instrument.MeterRegistry registry,
                           @org.springframework.beans.factory.annotation.Value("${ingest.valkey-ack:sync}") String ackMode,
                           @org.springframework.beans.factory.annotation.Value("${ingest.valkey-send:direct}") String sendMode,
                           @org.springframework.beans.factory.annotation.Value("${ingest.send-batch:512}") int sendBatch,
                           @org.springframework.beans.factory.annotation.Value("${ingest.send-linger-ms:2}") long sendLingerMs) {
        this.commands = connection.sync();
        this.mapper = mapper;
        this.stream = props.stream();
        this.maxStreamLength = props.maxStreamLength();
        this.asyncAck = "async".equalsIgnoreCase(ackMode);
        this.batchedSend = "batched".equalsIgnoreCase(sendMode);
        this.sendBatch = sendBatch;
        this.sendLingerMs = sendLingerMs;
        this.accumulator = batchedSend ? new java.util.concurrent.ArrayBlockingQueue<>(65_536) : null;
        this.senderConnection = batchedSend ? client.connect() : null;
        if (batchedSend) {
            senderConnection.setAutoFlushCommands(false);
            Thread.ofPlatform().name("valkey-sender").daemon().start(this::senderLoop);
            log.warn("ingest.valkey-send=batched (batch {} / linger {} ms): Kafka-producer-style "
                    + "accumulator; 202 is returned before Valkey acknowledges.", sendBatch, sendLingerMs);
        }
        this.asyncFailures = io.micrometer.core.instrument.Counter
                .builder("valkey.sink.async_failures")
                .description("XADDs that failed AFTER a 202 was already returned (async ack mode)")
                .register(registry);
        if (asyncAck) {
            log.warn("ingest.valkey-ack=async: 202 is returned BEFORE Valkey acknowledges. "
                    + "Events in flight are lost on failure (watch valkey.sink.async_failures).");
        }
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

    /**
     * The hot path: the raw element text goes onto the stream verbatim - zero
     * object binding in the receiver. Field-level validation happens where
     * the JSON is parsed anyway: the flusher (malformed entries are acked and
     * dropped loudly there).
     */
    @Override
    public int acceptAllRaw(java.util.List<String> rawEvents,
                            com.fasterxml.jackson.databind.ObjectMapper unused) {
        if (rawEvents.isEmpty() || overCapacity()) {
            return 0;
        }
        if (batchedSend) {
            int accepted = 0;
            for (String raw : rawEvents) {
                if (!accumulator.offer(raw)) {
                    break; // accumulator full = local backpressure -> 429 for the rest
                }
                accepted++;
            }
            sinceCheck.addAndGet(accepted);
            return accepted;
        }
        var async = commands.getStatefulConnection().async();
        io.lettuce.core.RedisFuture<String> last = null;
        for (String raw : rawEvents) {
            last = async.xadd(stream, Map.of(FIELD_JSON, raw));
        }
        sinceCheck.addAndGet(rawEvents.size());
        if (asyncAck) {
            // Fire-and-forget: 202 goes out now; a failed XADD after this
            // point is a LOST event. The completion callback only makes the
            // loss visible - it cannot un-send the 202.
            int n = rawEvents.size();
            last.whenComplete((id, failure) -> {
                if (failure != null) {
                    asyncFailures.increment(n);
                    log.warn("async XADD batch of {} failed after 202: {}", n, failure.toString());
                }
            });
            return rawEvents.size();
        }
        try {
            last.get(30, java.util.concurrent.TimeUnit.SECONDS);
            return rawEvents.size();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Interrupted while enqueueing batch", e);
        } catch (Exception e) {
            throw new IllegalStateException("Failed to enqueue batch to Valkey", e);
        }
    }

    /** Drain up to sendBatch events or sendLingerMs, ship as one pipelined flush. */
    private void senderLoop() {
        var async = senderConnection.async();
        java.util.List<String> batch = new java.util.ArrayList<>(sendBatch);
        while (!Thread.currentThread().isInterrupted()) {
            try {
                String first = accumulator.poll(sendLingerMs, java.util.concurrent.TimeUnit.MILLISECONDS);
                if (first == null) {
                    continue;
                }
                batch.add(first);
                long deadline = System.nanoTime() + sendLingerMs * 1_000_000;
                while (batch.size() < sendBatch && System.nanoTime() < deadline) {
                    String next = accumulator.poll();
                    if (next == null) {
                        java.util.concurrent.locks.LockSupport.parkNanos(50_000);
                        continue;
                    }
                    batch.add(next);
                }
                accumulator.drainTo(batch, sendBatch - batch.size());
                io.lettuce.core.RedisFuture<String> last = null;
                for (String raw : batch) {
                    last = async.xadd(stream, Map.of(FIELD_JSON, raw));
                }
                senderConnection.flushCommands();
                int n = batch.size();
                last.whenComplete((id, failure) -> {
                    if (failure != null) {
                        asyncFailures.increment(n);
                        log.warn("batched XADD flush of {} failed after 202: {}", n, failure.toString());
                    }
                });
                batch.clear();
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            } catch (Exception e) {
                asyncFailures.increment(batch.size());
                log.warn("valkey sender error ({} events): {}", batch.size(), e.toString());
                batch.clear();
            }
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
