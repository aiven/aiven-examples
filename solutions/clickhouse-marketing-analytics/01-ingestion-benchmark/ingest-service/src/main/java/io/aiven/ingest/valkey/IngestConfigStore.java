package io.aiven.ingest.valkey;

import io.lettuce.core.api.StatefulRedisConnection;
import io.lettuce.core.api.sync.RedisCommands;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

import java.util.Map;

/**
 * Runtime-tunable batch geometry, source-of-truth in Valkey itself: the
 * ingest:config hash holds batch_size and flush_interval_ms. Every flusher on
 * every app instance rereads it each cycle (one HGETALL per flush costs
 * nothing), so one PUT /config retunes the whole fleet immediately - no
 * redeploy, no restart, and the tuning survives deploys.
 *
 * No TTL anywhere: an expiry would silently retune the fleet to defaults
 * mid-traffic. If the hash is absent (fresh service, flushed DB), current()
 * falls back to the app defaults and re-seeds the hash - the system
 * self-heals.
 */
@Component
@ConditionalOnProperty(name = "ingest.buffer", havingValue = "valkey")
public class IngestConfigStore {

    static final String KEY = "ingest:config";
    static final String F_BATCH = "batch_size";
    static final String F_FLUSH = "flush_interval_ms";

    private final RedisCommands<String, String> commands;
    private final IngestTuning defaults;

    public IngestConfigStore(StatefulRedisConnection<String, String> connection,
                             @Value("${ingest.batch-size:10000}") int defaultBatchSize,
                             @Value("${ingest.flush-interval-ms:1000}") long defaultFlushIntervalMs) {
        this.commands = connection.sync();
        this.defaults = new IngestTuning(defaultBatchSize, defaultFlushIntervalMs);
    }

    /** The live tuning; seeds the hash with defaults when absent. */
    public IngestTuning current() {
        Map<String, String> hash = commands.hgetall(KEY);
        if (hash.isEmpty()) {
            seed(defaults);
            return defaults;
        }
        try {
            return new IngestTuning(
                    Integer.parseInt(hash.getOrDefault(F_BATCH, String.valueOf(defaults.batchSize()))),
                    Long.parseLong(hash.getOrDefault(F_FLUSH, String.valueOf(defaults.flushIntervalMs()))));
        } catch (RuntimeException corrupted) {
            // Out-of-bounds or non-numeric values (manual redis-cli edit):
            // fall back to defaults rather than stall the flusher.
            return defaults;
        }
    }

    /** Validate and persist; nulls keep the current value. Throws IllegalArgumentException on nonsense. */
    public IngestTuning update(Integer batchSize, Long flushIntervalMs) {
        IngestTuning now = current();
        IngestTuning next = new IngestTuning(
                batchSize != null ? batchSize : now.batchSize(),
                flushIntervalMs != null ? flushIntervalMs : now.flushIntervalMs());
        seed(next);
        return next;
    }

    private void seed(IngestTuning tuning) {
        commands.hset(KEY, Map.of(
                F_BATCH, String.valueOf(tuning.batchSize()),
                F_FLUSH, String.valueOf(tuning.flushIntervalMs())));
    }
}
