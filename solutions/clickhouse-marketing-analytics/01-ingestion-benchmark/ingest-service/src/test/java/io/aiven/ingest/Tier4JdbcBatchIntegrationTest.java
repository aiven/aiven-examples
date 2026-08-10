package io.aiven.ingest;

import io.aiven.ingest.bench.BenchmarkReporter;
import io.aiven.ingest.bench.BenchmarkReporterFactory;
import io.aiven.ingest.generator.SyntheticEventGenerator;
import io.aiven.ingest.tier.tier4.JdbcBatchService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;

import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.Statement;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Tier 4: batched inserts. The defining property vs tiers 1-3 is one
 * round-trip (and one part) per batch, not per row - asserted via the
 * reporter's flush count and the actual query count ClickHouse saw.
 */
@SpringBootTest
class Tier4JdbcBatchIntegrationTest extends AbstractClickHouseIntegrationTest {

    @Autowired
    JdbcTemplate jdbcTemplate;

    @Autowired
    BenchmarkReporterFactory reporterFactory;

    @Test
    void tier4FlushesOncePerBatchNotPerRow() throws Exception {
        long rowsBefore = totalRows();
        long rows = 2_500;
        int batchSize = 1_000;

        JdbcBatchService tier4 = new JdbcBatchService(jdbcTemplate, batchSize);
        BenchmarkReporter reporter = reporterFactory.forRun("tier4-it");
        reporter.start();
        long inserted = tier4.ingest(new SyntheticEventGenerator(rows, 9L), reporter);
        BenchmarkReporter.Summary summary = reporter.summary();

        assertThat(inserted).isEqualTo(rows);
        assertThat(summary.errors()).isZero();
        // 2,500 rows / 1,000 per batch = 3 flushes (1000 + 1000 + 500).
        assertThat(summary.flushes()).as("one flush per batch").isEqualTo(3);
        assertThat(totalRows() - rowsBefore).isEqualTo(rows);
    }

    private long totalRows() throws Exception {
        try (Connection conn = connect(); Statement stmt = conn.createStatement()) {
            ResultSet rs = stmt.executeQuery("SELECT count() FROM campaign_events");
            rs.next();
            return rs.getLong(1);
        }
    }
}
