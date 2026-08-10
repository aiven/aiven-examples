package io.aiven.ingest.api;

import io.aiven.ingest.bench.BenchmarkReporter;
import io.aiven.ingest.bench.BenchmarkReporterFactory;
import io.aiven.ingest.generator.SyntheticEventGenerator;
import io.aiven.ingest.tier.IngestTier;
import io.aiven.ingest.tier.tier1.RowByRowJdbcService;
import io.aiven.ingest.tier.tier2.AsyncInsertService;
import io.aiven.ingest.tier.tier4.JdbcBatchService;
import io.aiven.ingest.tier.rest.BufferedIngestService;
import io.aiven.ingest.tier.tier5.NativeStreamService;
import io.aiven.ingest.tier.tier6.ParallelStreamRunner;
import com.clickhouse.client.api.Client;
import jakarta.annotation.PreDestroy;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Lazy;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Runs API-triggered benchmarks (the remote twin of TierBenchmarkRunner's CLI
 * mode, for when the service is deployed next to the data - e.g. Aiven Apps -
 * and there is no terminal to read). Each request builds a FRESH tier instance
 * from the request's parameters, so batch size / writers / format are per-run,
 * not boot-time config.
 *
 * Exactly one run executes at a time: overlapping runs would share the
 * connection pools and the server's merge capacity, corrupting both numbers.
 * A second POST while busy gets a 409 with the active run's id.
 */
@Service
public class BenchmarkRunService {

    private static final Logger log = LoggerFactory.getLogger(BenchmarkRunService.class);

    private final JdbcTemplate jdbcTemplate;
    private final JdbcTemplate asyncInsertJdbcTemplate;
    private final Client client;
    private final BenchmarkReporterFactory reporterFactory;

    private final long defaultRows;
    private final long defaultSeed;
    private final int defaultBatchSize;
    private final int defaultConcurrency;
    private final String defaultFormat;
    private final int defaultWriters;
    private final int defaultBufferCapacity;
    private final long defaultFlushIntervalMs;

    private final ExecutorService runner = Executors.newSingleThreadExecutor(
            Thread.ofPlatform().name("benchmark-runner").factory());
    private final Map<String, BenchmarkRun> runsById = new ConcurrentHashMap<>();
    private final List<BenchmarkRun> runsInOrder = new CopyOnWriteArrayList<>();
    private final AtomicReference<BenchmarkRun> active = new AtomicReference<>();
    private final AtomicInteger sequence = new AtomicInteger();

    public BenchmarkRunService(JdbcTemplate jdbcTemplate,
                               @Qualifier("asyncInsert") JdbcTemplate asyncInsertJdbcTemplate,
                               @Lazy Client client,
                               BenchmarkReporterFactory reporterFactory,
                               @Value("${ingest.rows:100000}") long defaultRows,
                               @Value("${ingest.seed:42}") long defaultSeed,
                               @Value("${ingest.batch-size:10000}") int defaultBatchSize,
                               @Value("${ingest.concurrency:1}") int defaultConcurrency,
                               @Value("${ingest.format:RowBinary}") String defaultFormat,
                               @Value("${ingest.writers:4}") int defaultWriters,
                               @Value("${ingest.buffer-capacity:100000}") int defaultBufferCapacity,
                               @Value("${ingest.flush-interval-ms:1000}") long defaultFlushIntervalMs) {
        this.jdbcTemplate = jdbcTemplate;
        this.asyncInsertJdbcTemplate = asyncInsertJdbcTemplate;
        this.client = client;
        this.reporterFactory = reporterFactory;
        this.defaultRows = defaultRows;
        this.defaultSeed = defaultSeed;
        this.defaultBatchSize = defaultBatchSize;
        this.defaultConcurrency = defaultConcurrency;
        this.defaultFormat = defaultFormat;
        this.defaultWriters = defaultWriters;
        this.defaultBufferCapacity = defaultBufferCapacity;
        this.defaultFlushIntervalMs = defaultFlushIntervalMs;
    }

    /** @throws IllegalArgumentException on bad parameters (400) */
    public BenchmarkRun start(BenchmarkRequest request) {
        Params p = resolve(request);
        IngestTier tier = buildTier(p);

        String id = "run-%03d-tier%s".formatted(sequence.incrementAndGet(), p.tierLabel());
        BenchmarkReporter reporter = reporterFactory.forRun(id);
        BenchmarkRun run = new BenchmarkRun(id, p.tier, tier.description(), p.asMap(), p.rows, reporter);

        if (!active.compareAndSet(null, run)) {
            throw new BenchmarkBusyException(active.get());
        }
        runsById.put(id, run);
        runsInOrder.add(run);

        // Start the clock before submitting: status polls call summary(),
        // which needs a start time even if the task hasn't been scheduled yet.
        reporter.start();
        runner.submit(() -> {
            log.info("[{}] starting: {} rows through tier {} [{}]", id, p.rows, p.tier, tier.description());
            Exception failure = null;
            try {
                tier.ingest(new SyntheticEventGenerator(p.rows, p.seed), reporter);
                reporter.report(); // logs the table + appends the CSV line, same as CLI runs
            } catch (Exception e) {
                failure = e;
            }
            // Free the single-flight slot BEFORE flipping the state: a caller
            // that sees COMPLETED must be able to start the next run at once.
            active.compareAndSet(run, null);
            if (failure == null) {
                run.completed();
                log.info("[{}] completed", id);
            } else {
                run.failed(failure);
                log.error("[{}] failed", id, failure);
            }
        });
        return run;
    }

    public BenchmarkRun get(String id) {
        return runsById.get(id);
    }

    public List<BenchmarkRun> all() {
        return List.copyOf(runsInOrder);
    }

    private IngestTier buildTier(Params p) {
        return switch (p.tier) {
            case 1 -> new RowByRowJdbcService(jdbcTemplate);
            case 2 -> new AsyncInsertService(asyncInsertJdbcTemplate, 1);
            case 3 -> new AsyncInsertService(asyncInsertJdbcTemplate,
                    p.concurrency > 1 ? p.concurrency : 80);
            case 4 -> new JdbcBatchService(jdbcTemplate, p.batchSize);
            case 5 -> new NativeStreamService(client, p.batchSize, p.format);
            case 6 -> new ParallelStreamRunner(
                    new NativeStreamService(client, p.batchSize, p.format), p.writers, p.batchSize);
            // 0 = off the ladder: the buffered REST ingestion pipeline.
            case 0 -> new BufferedIngestService(new JdbcBatchService(jdbcTemplate, p.batchSize),
                    p.bufferCapacity, p.batchSize, p.flushIntervalMs);
            default -> throw new IllegalArgumentException(
                    "tier must be 1..6 (ladder) or 0 (buffered REST pipeline), got " + p.tier);
        };
    }

    private Params resolve(BenchmarkRequest r) {
        if (r == null || r.tier() == null) {
            throw new IllegalArgumentException("'tier' is required (1..6, or 0 for the buffered REST pipeline)");
        }
        Params p = new Params();
        p.tier = r.tier();
        p.rows = positive("rows", r.rows() != null ? r.rows() : defaultRows);
        p.seed = r.seed() != null ? r.seed() : defaultSeed;
        p.batchSize = (int) positive("batch_size", r.batchSize() != null ? r.batchSize() : defaultBatchSize);
        p.concurrency = (int) positive("concurrency", r.concurrency() != null ? r.concurrency() : defaultConcurrency);
        p.format = r.format() != null ? r.format() : defaultFormat;
        p.writers = (int) positive("writers", r.writers() != null ? r.writers() : defaultWriters);
        p.bufferCapacity = (int) positive("buffer_capacity",
                r.bufferCapacity() != null ? r.bufferCapacity() : defaultBufferCapacity);
        p.flushIntervalMs = positive("flush_interval_ms",
                r.flushIntervalMs() != null ? r.flushIntervalMs() : defaultFlushIntervalMs);
        return p;
    }

    private static long positive(String name, long value) {
        if (value <= 0) {
            throw new IllegalArgumentException("'" + name + "' must be > 0, got " + value);
        }
        return value;
    }

    @PreDestroy
    void shutdown() {
        runner.shutdownNow();
    }

    /** Resolved, defaulted parameters of one run. */
    private static final class Params {
        int tier;
        long rows;
        long seed;
        int batchSize;
        int concurrency;
        String format;
        int writers;
        int bufferCapacity;
        long flushIntervalMs;

        String tierLabel() {
            return String.valueOf(tier);
        }

        /** Echoed back in status responses: only what the tier actually uses. */
        Map<String, Object> asMap() {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("rows", rows);
            m.put("seed", seed);
            switch (tier) {
                case 3 -> m.put("concurrency", concurrency > 1 ? concurrency : 80);
                case 4 -> m.put("batch_size", batchSize);
                case 0 -> {
                    m.put("batch_size", batchSize);
                    m.put("buffer_capacity", bufferCapacity);
                    m.put("flush_interval_ms", flushIntervalMs);
                }
                case 5 -> {
                    m.put("batch_size", batchSize);
                    m.put("format", format);
                }
                case 6 -> {
                    m.put("batch_size", batchSize);
                    m.put("format", format);
                    m.put("writers", writers);
                }
                default -> { }
            }
            return m;
        }
    }

    /** 409: a run is already executing. */
    public static final class BenchmarkBusyException extends RuntimeException {
        private final transient BenchmarkRun activeRun;

        BenchmarkBusyException(BenchmarkRun activeRun) {
            super("benchmark " + (activeRun != null ? activeRun.id() : "?") + " is already running");
            this.activeRun = activeRun;
        }

        public BenchmarkRun activeRun() {
            return activeRun;
        }
    }
}
