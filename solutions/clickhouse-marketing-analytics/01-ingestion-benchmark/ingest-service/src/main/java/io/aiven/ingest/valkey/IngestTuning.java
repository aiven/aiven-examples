package io.aiven.ingest.valkey;

/**
 * The two knobs of batch geometry, tunable at runtime through the ingest:config
 * hash in Valkey (see IngestConfigStore). Bounds keep a fat-fingered PUT from
 * stalling ingestion (batch too small -> parts explosion; interval too long ->
 * unbounded event->queryable latency).
 */
public record IngestTuning(int batchSize, long flushIntervalMs) {

    public static final int MIN_BATCH = 100;
    public static final int MAX_BATCH = 1_000_000;
    public static final long MIN_FLUSH_MS = 50;
    public static final long MAX_FLUSH_MS = 60_000;

    public IngestTuning {
        if (batchSize < MIN_BATCH || batchSize > MAX_BATCH) {
            throw new IllegalArgumentException(
                    "batch_size must be in [" + MIN_BATCH + ", " + MAX_BATCH + "], got " + batchSize);
        }
        if (flushIntervalMs < MIN_FLUSH_MS || flushIntervalMs > MAX_FLUSH_MS) {
            throw new IllegalArgumentException(
                    "flush_interval_ms must be in [" + MIN_FLUSH_MS + ", " + MAX_FLUSH_MS + "], got " + flushIntervalMs);
        }
    }
}
