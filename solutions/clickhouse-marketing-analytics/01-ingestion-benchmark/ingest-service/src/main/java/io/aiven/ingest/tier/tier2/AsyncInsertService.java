package io.aiven.ingest.tier.tier2;

import io.aiven.ingest.bench.BenchmarkReporter;
import io.aiven.ingest.model.CampaignEvent;
import io.aiven.ingest.tier.IngestTier;
import io.aiven.ingest.tier.tier1.RowByRowJdbcService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;

import java.sql.Timestamp;
import java.util.Iterator;
import java.util.concurrent.Executors;
import java.util.concurrent.Semaphore;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Tier 2 - async_insert done right: the SQL and the row-by-row loop are
 * byte-for-byte tier 1; the only change is the connection it runs on (see
 * ClickHouseJdbcConfig: the async-insert pool's JDBC URL carries
 * async_insert=1, wait_for_async_insert=0, tuned buffer settings). The server
 * buffers many small inserts into one part: no more part explosion, and the
 * rollup MV fires once per flushed block instead of once per row. What it does
 * NOT fix: each row is still one HTTP round-trip, so single-threaded
 * throughput stays ~1/RTT - that ceiling is the demo point.
 *
 * Tier 3 - the same code with concurrency > 1: async_insert is designed
 * for many concurrent small writers, so N virtual-thread senders scale
 * throughput to ~concurrency/RTT. Cap at ~80 against Aiven: every in-flight
 * INSERT counts against the hard 100-concurrent-queries-per-16GB plan limit
 * (leave headroom for dashboards).
 *
 * One class, two rungs: tier() reports 2 sequential, 3 concurrent - the Spring
 * beans for both are defined in AsyncInsertTiersConfig.
 */
public class AsyncInsertService implements IngestTier {

    private static final Logger log = LoggerFactory.getLogger(AsyncInsertService.class);
    static final int AIVEN_SAFE_MAX_CONCURRENCY = 80;

    // Deliberately tier 1's exact statement: the fix is connection config, not SQL.
    static final String INSERT_SQL = RowByRowJdbcService.INSERT_SQL;

    private final JdbcTemplate jdbcTemplate;
    private final int concurrency;

    public AsyncInsertService(JdbcTemplate asyncInsertJdbcTemplate, int concurrency) {
        this.jdbcTemplate = asyncInsertJdbcTemplate;
        this.concurrency = concurrency;
    }

    @Override
    public int tier() {
        return concurrency > 1 ? 3 : 2;
    }

    @Override
    public String description() {
        return concurrency > 1
                ? "async_insert + " + concurrency + " concurrent virtual-thread senders (tier 3)"
                : "async_insert tuned, row-by-row (config-only fix)";
    }

    @Override
    public long ingest(Iterator<CampaignEvent> events, BenchmarkReporter reporter) throws Exception {
        if (concurrency > AIVEN_SAFE_MAX_CONCURRENCY) {
            log.warn("concurrency={} exceeds the Aiven-safe cap of {} (hard plan limit: 100 concurrent "
                            + "queries per 16GB RAM, minus headroom for dashboards) - expect rejections",
                    concurrency, AIVEN_SAFE_MAX_CONCURRENCY);
        }
        return concurrency > 1 ? ingestConcurrent(events, reporter) : ingestSequential(events, reporter);
    }

    private long ingestSequential(Iterator<CampaignEvent> events, BenchmarkReporter reporter) {
        long inserted = 0;
        while (events.hasNext()) {
            if (insertOne(events.next(), reporter)) {
                inserted++;
            }
        }
        return inserted;
    }

    /**
     * Tier 3: per-event sends are ~99% RTT wait - the textbook virtual-thread
     * case (Java 25: no synchronized pinning, JEP 491). The semaphore bounds
     * in-flight requests; the Hikari pool must be at least as large or blocked
     * threads gain nothing (see spring.datasource.hikari in application.yml).
     */
    private long ingestConcurrent(Iterator<CampaignEvent> events, BenchmarkReporter reporter)
            throws InterruptedException {
        AtomicLong inserted = new AtomicLong();
        Semaphore inFlight = new Semaphore(concurrency);
        try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {
            while (events.hasNext()) {
                CampaignEvent event = events.next();
                inFlight.acquire();
                executor.submit(() -> {
                    try {
                        if (insertOne(event, reporter)) {
                            inserted.incrementAndGet();
                        }
                    } finally {
                        inFlight.release();
                    }
                });
            }
        } // close() waits for all in-flight tasks
        return inserted.get();
    }

    private boolean insertOne(CampaignEvent e, BenchmarkReporter reporter) {
        long t0 = System.nanoTime();
        try {
            jdbcTemplate.update(INSERT_SQL,
                    Timestamp.from(e.eventTime()), e.eventType(), e.userId(), e.sessionId(),
                    e.campaignId(), e.channel(), e.source(), e.medium(), e.adGroup(),
                    e.keyword(), e.landingPage(), e.conversionValue(), e.currency(),
                    e.country(), e.deviceType(), e.properties());
            reporter.recordFlush(1, System.nanoTime() - t0);
            return true;
        } catch (RuntimeException ex) {
            reporter.recordError(ex);
            return false;
        }
    }
}
