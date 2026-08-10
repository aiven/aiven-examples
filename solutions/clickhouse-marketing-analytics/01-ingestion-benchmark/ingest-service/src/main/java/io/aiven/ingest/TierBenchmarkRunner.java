package io.aiven.ingest;

import io.aiven.ingest.bench.BenchmarkReporter;
import io.aiven.ingest.bench.BenchmarkReporterFactory;
import io.aiven.ingest.config.ClickHouseProperties;
import io.aiven.ingest.generator.SyntheticEventGenerator;
import io.aiven.ingest.tier.IngestTier;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

import java.util.List;

/**
 * Selects the ladder rung and runs one benchmark:
 *
 *   java -jar ingest-service.jar --tier=1 --rows=100000 [--spring.profiles.active=aiven]
 *
 * Without --tier (or with tier=-1) the app just starts (REST service mode:
 * POST /events); with it, it ingests --rows synthetic events through that tier,
 * prints the benchmark table, and exits. Tiers 1..6 are the ladder; tier 0 is
 * the off-ladder buffered REST pipeline benchmark.
 */
@Component
public class TierBenchmarkRunner implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(TierBenchmarkRunner.class);

    private final List<IngestTier> tiers;
    private final BenchmarkReporterFactory reporterFactory;
    private final ClickHouseProperties clickHouse;
    private final int tier;
    private final long rows;
    private final long seed;

    public TierBenchmarkRunner(List<IngestTier> tiers,
                               BenchmarkReporterFactory reporterFactory,
                               ClickHouseProperties clickHouse,
                               @Value("${ingest.tier:-1}") int tier,
                               @Value("${ingest.rows:100000}") long rows,
                               @Value("${ingest.seed:42}") long seed) {
        this.tiers = tiers;
        this.reporterFactory = reporterFactory;
        this.clickHouse = clickHouse;
        this.tier = tier;
        this.rows = rows;
        this.seed = seed;
    }

    @Override
    public void run(ApplicationArguments args) throws Exception {
        if (tier < 0) {
            log.info("No --tier given; running as a plain service. Tiers available: {}",
                    tiers.stream().map(t -> t.tier() + "=" + t.description()).toList());
            return;
        }
        IngestTier selected = tiers.stream()
                .filter(t -> t.tier() == tier)
                .findFirst()
                .orElseThrow(() -> new IllegalArgumentException(
                        "Unknown tier " + tier + " (valid: 1..6 for the ladder, 0 for the buffered REST pipeline)"));

        String label = "tier" + tier;
        log.info("Running {} [{}] -> {}/{} with {} rows (seed {})",
                label, selected.description(), clickHouse.host(), clickHouse.database(), rows, seed);

        BenchmarkReporter reporter = reporterFactory.forRun(label);
        reporter.start();
        long inserted = selected.ingest(new SyntheticEventGenerator(rows, seed), reporter);
        BenchmarkReporter.Summary summary = reporter.report();
        log.info("{} finished: {} rows handed to server, {} errors", label, inserted, summary.errors());
    }
}
