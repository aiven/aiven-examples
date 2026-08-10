package io.aiven.ingest;

import io.aiven.ingest.bench.BenchmarkReporter;
import io.aiven.ingest.bench.BenchmarkReporterFactory;
import io.aiven.ingest.generator.SyntheticEventGenerator;
import io.aiven.ingest.tier.tier5.NativeStreamService;
import io.aiven.ingest.tier.tier6.ParallelStreamRunner;
import com.clickhouse.client.api.Client;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.Statement;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Tier 6: N writers x tier 5 batches. The invariant vs tier 5 is unchanged
 * flush accounting (one flush per batch, no lost or duplicated rows) - only
 * the wall-clock changes.
 */
@SpringBootTest
class Tier6ParallelStreamIntegrationTest extends AbstractClickHouseIntegrationTest {

    @Autowired
    Client client;

    @Autowired
    BenchmarkReporterFactory reporterFactory;

    @Test
    void parallelWritersLoseNothingAndKeepBatchAccounting() throws Exception {
        long rowsBefore = totalRows();
        long rows = 10_000;
        int batchSize = 1_000;

        NativeStreamService tier4 = new NativeStreamService(client, batchSize, "RowBinary");
        ParallelStreamRunner tier5 = new ParallelStreamRunner(tier4, 4, batchSize);
        BenchmarkReporter reporter = reporterFactory.forRun("tier6-it");
        reporter.start();
        long inserted = tier5.ingest(new SyntheticEventGenerator(rows, 13L), reporter);
        BenchmarkReporter.Summary summary = reporter.summary();

        assertThat(inserted).isEqualTo(rows);
        assertThat(summary.errors()).isZero();
        assertThat(summary.flushes()).as("one flush per batch across all writers").isEqualTo(10);
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
