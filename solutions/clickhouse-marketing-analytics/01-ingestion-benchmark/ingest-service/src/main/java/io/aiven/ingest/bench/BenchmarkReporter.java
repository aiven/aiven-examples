package io.aiven.ingest.bench;

import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.time.Duration;
import java.time.Instant;
import java.util.Locale;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Per-run benchmark accounting: a Micrometer timer per flush plus row/error
 * counters. One instance = one benchmark run (create via BenchmarkReporterFactory).
 *
 * "Flush" means one round-trip to ClickHouse: a single row for tier 1, a batch
 * for Tiers 2+. summary() prints the human table (rows/s, flush p50/p99, errors)
 * and appends a CSV line to benchmark-results.csv - that file accumulates into
 * the ladder table for the README.
 */
public final class BenchmarkReporter {

    private static final Logger log = LoggerFactory.getLogger(BenchmarkReporter.class);
    // Overridable so tests don't pollute the repo's raw results file
    // (see ingest.results-csv in AbstractClickHouseIntegrationTest).
    private static final Path CSV = Path.of(System.getProperty(
            "ingest.results-csv", "benchmark-results.csv"));
    private static final String CSV_HEADER =
            "timestamp,run,rows,wall_seconds,rows_per_sec,flushes,flush_p50_ms,flush_p99_ms,errors\n";

    private final String runLabel;
    private final Timer flushTimer;
    private final io.micrometer.core.instrument.Counter rowsCounter;
    private final io.micrometer.core.instrument.Counter errorsCounter;
    private final AtomicLong rows = new AtomicLong();
    private final AtomicLong errors = new AtomicLong();
    private volatile Instant startedAt;
    private volatile Instant finishedAt;

    BenchmarkReporter(MeterRegistry registry, String runLabel) {
        this.runLabel = runLabel;
        this.flushTimer = Timer.builder("ingest.flush")
                .tag("run", runLabel)
                .publishPercentiles(0.5, 0.99)
                // Bucketed histogram so Grafana can histogram_quantile() over
                // the OTLP -> Thanos pipeline, not just read local percentiles.
                .publishPercentileHistogram()
                .register(registry);
        // Real meters (not just the local AtomicLongs) so rows/errors flow
        // out through the OTLP exporter to Thanos/Grafana.
        this.rowsCounter = io.micrometer.core.instrument.Counter.builder("ingest.rows")
                .tag("run", runLabel)
                .description("rows successfully handed to ClickHouse")
                .register(registry);
        this.errorsCounter = io.micrometer.core.instrument.Counter.builder("ingest.errors")
                .tag("run", runLabel)
                .description("failed insert round-trips")
                .register(registry);
    }

    public void start() {
        startedAt = Instant.now();
    }

    /** Record one successful round-trip that wrote {@code rowCount} rows. */
    public void recordFlush(long rowCount, long durationNanos) {
        flushTimer.record(durationNanos, TimeUnit.NANOSECONDS);
        rows.addAndGet(rowCount);
        rowsCounter.increment(rowCount);
    }

    public void recordError(Throwable t) {
        errors.incrementAndGet();
        errorsCounter.increment();
        log.warn("[{}] insert error: {}", runLabel, t.toString());
    }

    public long rowsInserted() {
        return rows.get();
    }

    public long errorCount() {
        return errors.get();
    }

    public Summary finish() {
        finishedAt = Instant.now();
        return summary();
    }

    public Summary summary() {
        Instant end = finishedAt != null ? finishedAt : Instant.now();
        double wallSeconds = Math.max(Duration.between(startedAt, end).toNanos() / 1e9, 1e-9);
        var snapshot = flushTimer.takeSnapshot();
        double p50 = 0, p99 = 0;
        for (var pv : snapshot.percentileValues()) {
            if (pv.percentile() == 0.5) p50 = pv.value(TimeUnit.MILLISECONDS);
            if (pv.percentile() == 0.99) p99 = pv.value(TimeUnit.MILLISECONDS);
        }
        return new Summary(runLabel, rows.get(), wallSeconds, rows.get() / wallSeconds,
                snapshot.count(), p50, p99, errors.get());
    }

    /** Print the summary table and append the CSV line for the ladder table. */
    public Summary report() {
        Summary s = finish();
        log.info("\n{}", s.render());
        appendCsv(s);
        return s;
    }

    private void appendCsv(Summary s) {
        String line = String.format(Locale.ROOT, "%s,%s,%d,%.2f,%.0f,%d,%.2f,%.2f,%d%n",
                Instant.now(), s.run(), s.rows(), s.wallSeconds(), s.rowsPerSec(),
                s.flushes(), s.flushP50Ms(), s.flushP99Ms(), s.errors());
        try {
            if (Files.notExists(CSV)) {
                Files.writeString(CSV, CSV_HEADER, StandardCharsets.UTF_8, StandardOpenOption.CREATE);
            }
            Files.writeString(CSV, line, StandardCharsets.UTF_8, StandardOpenOption.APPEND);
        } catch (IOException e) {
            log.warn("could not append to {}: {}", CSV, e.toString());
        }
    }

    public record Summary(String run, long rows, double wallSeconds, double rowsPerSec,
                          long flushes, double flushP50Ms, double flushP99Ms, long errors) {

        public String render() {
            return String.format(Locale.ROOT, """
                    ================ Benchmark: %s ================
                    rows inserted : %,d
                    wall time     : %.2f s
                    throughput    : %,.0f rows/s
                    flushes       : %,d
                    flush p50/p99 : %.2f ms / %.2f ms
                    errors        : %,d
                    ================================================""",
                    run, rows, wallSeconds, rowsPerSec, flushes, flushP50Ms, flushP99Ms, errors);
        }
    }
}
