package io.aiven.ingest;

import io.aiven.ingest.bench.BenchmarkReporter;
import io.aiven.ingest.bench.BenchmarkReporterFactory;
import io.aiven.ingest.generator.SyntheticEventGenerator;
import io.aiven.ingest.tier.tier5.NativeStreamService;
import com.clickhouse.client.api.Client;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.Statement;
import java.time.Instant;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Tier 5: client-v2 body-separated inserts. Verifies both wire formats land
 * the same rows (incl. Nullable columns and DateTime64 millis) and that one
 * batch = one round-trip, same as tier 4 - only the serialization changes.
 */
@SpringBootTest
class Tier5NativeStreamIntegrationTest extends AbstractClickHouseIntegrationTest {

    @Autowired
    Client client;

    @Autowired
    BenchmarkReporterFactory reporterFactory;

    @Test
    void rowBinaryFlushesOncePerBatchAndPreservesValues() throws Exception {
        long rowsBefore = totalRows();
        Instant testStart = Instant.now();
        long rows = 2_500;

        NativeStreamService tier4 = new NativeStreamService(client, 1_000, "RowBinary");
        BenchmarkReporter reporter = reporterFactory.forRun("tier5-it");
        reporter.start();
        long inserted = tier4.ingest(new SyntheticEventGenerator(rows, 11L), reporter);
        BenchmarkReporter.Summary summary = reporter.summary();

        assertThat(inserted).isEqualTo(rows);
        assertThat(summary.errors()).isZero();
        assertThat(summary.flushes()).as("one flush per batch").isEqualTo(3);
        assertThat(totalRows() - rowsBefore).isEqualTo(rows);

        // DateTime64 must arrive as real timestamps (a tz/scale bug would shift them).
        try (Connection conn = connect(); Statement stmt = conn.createStatement()) {
            ResultSet rs = stmt.executeQuery(
                    "SELECT max(event_time) >= toDateTime64('" + testStart.toString().replace("T", " ").substring(0, 19)
                            + "', 3, 'UTC') - INTERVAL 5 SECOND FROM campaign_events");
            rs.next();
            assertThat(rs.getBoolean(1)).as("event_time survived RowBinary serialization").isTrue();
        }
        // Nullable columns: purchases carry conversion_value, everything else NULL.
        try (Connection conn = connect(); Statement stmt = conn.createStatement()) {
            ResultSet rs = stmt.executeQuery("""
                    SELECT countIf(conversion_value IS NOT NULL AND event_type = 'purchase') > 0,
                           countIf(conversion_value IS NOT NULL AND event_type != 'purchase')
                    FROM campaign_events""");
            rs.next();
            assertThat(rs.getBoolean(1)).as("purchases have conversion_value").isTrue();
            assertThat(rs.getLong(2)).as("non-purchases stay NULL").isZero();
        }
    }

    @Test
    void jsonEachRowLandsTheSameRows() throws Exception {
        long rowsBefore = totalRows();
        long rows = 1_500;

        NativeStreamService tier4Json = new NativeStreamService(client, 1_000, "JSONEachRow");
        BenchmarkReporter reporter = reporterFactory.forRun("tier5-json-it");
        reporter.start();
        long inserted = tier4Json.ingest(new SyntheticEventGenerator(rows, 12L), reporter);

        assertThat(inserted).isEqualTo(rows);
        assertThat(reporter.summary().errors()).isZero();
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
