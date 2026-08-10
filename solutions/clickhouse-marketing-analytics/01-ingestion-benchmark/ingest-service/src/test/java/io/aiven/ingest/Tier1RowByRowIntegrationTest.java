package io.aiven.ingest;

import io.aiven.ingest.bench.BenchmarkReporter;
import io.aiven.ingest.bench.BenchmarkReporterFactory;
import io.aiven.ingest.generator.SyntheticEventGenerator;
import io.aiven.ingest.tier.tier1.RowByRowJdbcService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.Statement;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Baseline acceptance, verified end to end against a real ClickHouse:
 * Tier 1 (row-by-row JDBC) ingests through the full Spring wiring, the
 * BenchmarkReporter produces the rows/s / p99 / errors table, and system.parts
 * shows the many-small-parts pattern that is tier 1's failure mode. The same
 * run against Aiven is a config switch (--spring.profiles.active=aiven).
 */
@SpringBootTest
class Tier1RowByRowIntegrationTest extends AbstractClickHouseIntegrationTest {

    private static final long ROWS = 1_500;

    @Autowired
    RowByRowJdbcService tier1;

    @Autowired
    BenchmarkReporterFactory reporterFactory;

    @Test
    void tier1IngestsRowByRowAndReportsBenchmark() throws Exception {
        BenchmarkReporter reporter = reporterFactory.forRun("tier1-it");
        reporter.start();
        long inserted = tier1.ingest(new SyntheticEventGenerator(ROWS, 42L), reporter);
        BenchmarkReporter.Summary summary = reporter.summary();

        assertThat(inserted).isEqualTo(ROWS);
        assertThat(summary.errors()).isZero();
        assertThat(summary.rows()).isEqualTo(ROWS);
        assertThat(summary.flushes()).as("row-by-row: one flush per row").isEqualTo(ROWS);
        assertThat(summary.rowsPerSec()).isPositive();
        assertThat(summary.flushP99Ms()).isPositive();
        assertThat(summary.render()).contains("rows/s").contains("errors");

        try (Connection conn = connect(); Statement stmt = conn.createStatement()) {
            ResultSet rs = stmt.executeQuery(
                    "SELECT count() FROM campaign_events WHERE user_id LIKE 'u%'");
            rs.next();
            assertThat(rs.getLong(1)).isGreaterThanOrEqualTo(ROWS);

            // The tier 1 disease: every insert created its own part. Background
            // merges may already have collapsed the *active* set, but merged-away
            // parts stay visible (inactive) for old_parts_lifetime, so counting
            // all parts shows the one-part-per-insert churn the live demo
            // displays via shared/schema/03_diagnostics.sql.
            rs = stmt.executeQuery("""
                    SELECT count() FROM system.parts
                    WHERE database = 'campaign_analytics'
                      AND table = 'campaign_events'""");
            rs.next();
            assertThat(rs.getLong(1))
                    .as("parts (active + not-yet-dropped) after %d row-by-row inserts", ROWS)
                    .isGreaterThan(10);
        }
    }
}
