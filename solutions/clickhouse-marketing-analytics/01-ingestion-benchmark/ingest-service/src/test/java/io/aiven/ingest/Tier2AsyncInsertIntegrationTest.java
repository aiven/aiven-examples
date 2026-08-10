package io.aiven.ingest;

import io.aiven.ingest.bench.BenchmarkReporter;
import io.aiven.ingest.bench.BenchmarkReporterFactory;
import io.aiven.ingest.generator.SyntheticEventGenerator;
import io.aiven.ingest.tier.tier2.AsyncInsertService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;

import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.Statement;
import java.time.Duration;
import java.time.Instant;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Tiers 2-3: row-by-row inserts with async_insert settings on the query.
 * Verifies the settings actually engage server-side (system.events
 * AsyncInsertQuery counter) - the exact check for the customer's
 * "settings were right in spirit but did they apply?" doubt - and that
 * wait_for_async_insert=0 rows become visible after the server-side flush.
 */
@SpringBootTest
class Tier2AsyncInsertIntegrationTest extends AbstractClickHouseIntegrationTest {

    @Autowired
    @Qualifier("tier2AsyncSequential")
    AsyncInsertService tier2;   // the sequential rung: concurrency = 1

    @Autowired
    @Qualifier("asyncInsert")
    JdbcTemplate asyncInsertJdbcTemplate;

    @Autowired
    BenchmarkReporterFactory reporterFactory;

    @Test
    void tier2EngagesAsyncInsertAndRowsBecomeVisible() throws Exception {
        long asyncBefore = asyncInsertQueryCount();
        long rowsBefore = totalRows();
        long rows = 300;

        BenchmarkReporter reporter = reporterFactory.forRun("tier2-it");
        reporter.start();
        long inserted = tier2.ingest(new SyntheticEventGenerator(rows, 7L), reporter);

        assertThat(inserted).isEqualTo(rows);
        assertThat(reporter.errorCount()).isZero();
        // The server must have taken these through the async_insert path.
        assertThat(asyncInsertQueryCount() - asyncBefore)
                .as("AsyncInsertQuery counter delta").isGreaterThanOrEqualTo(rows);
        // Fire-and-forget: rows appear after async_insert_busy_timeout_ms (1s).
        awaitRowCount(rowsBefore + rows, Duration.ofSeconds(10));
    }

    @Test
    void tier3ConcurrentSendersIngestEverything() throws Exception {
        long rowsBefore = totalRows();
        long rows = 1_000;

        AsyncInsertService tier3 = new AsyncInsertService(asyncInsertJdbcTemplate, 16);
        assertThat(tier3.description()).contains("tier 3").contains("16");

        BenchmarkReporter reporter = reporterFactory.forRun("tier3-it");
        reporter.start();
        long inserted = tier3.ingest(new SyntheticEventGenerator(rows, 8L), reporter);

        assertThat(inserted).isEqualTo(rows);
        assertThat(reporter.errorCount()).isZero();
        assertThat(reporter.summary().flushes()).isEqualTo(rows);
        awaitRowCount(rowsBefore + rows, Duration.ofSeconds(10));
    }

    private long asyncInsertQueryCount() throws Exception {
        try (Connection conn = connect(); Statement stmt = conn.createStatement()) {
            ResultSet rs = stmt.executeQuery(
                    "SELECT value FROM system.events WHERE event = 'AsyncInsertQuery'");
            return rs.next() ? rs.getLong(1) : 0;
        }
    }

    private long totalRows() throws Exception {
        try (Connection conn = connect(); Statement stmt = conn.createStatement()) {
            ResultSet rs = stmt.executeQuery("SELECT count() FROM campaign_events");
            rs.next();
            return rs.getLong(1);
        }
    }

    private void awaitRowCount(long expected, Duration timeout) throws Exception {
        Instant deadline = Instant.now().plus(timeout);
        long seen = -1;
        while (Instant.now().isBefore(deadline)) {
            seen = totalRows();
            if (seen >= expected) return;
            Thread.sleep(250);
        }
        assertThat(seen).as("rows visible after async flush timeout").isGreaterThanOrEqualTo(expected);
    }
}
