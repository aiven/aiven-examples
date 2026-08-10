package io.aiven.ingest;

import io.aiven.ingest.bench.BenchmarkReporter;
import io.aiven.ingest.bench.BenchmarkReporterFactory;
import io.aiven.ingest.generator.SyntheticEventGenerator;
import io.aiven.ingest.model.CampaignEvent;
import io.aiven.ingest.tier.tier4.JdbcBatchService;
import io.aiven.ingest.tier.rest.BufferedIngestService;
import io.aiven.ingest.tier.rest.EventBuffer;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;

import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.Statement;
import java.time.Duration;
import java.time.Instant;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.concurrent.CountDownLatch;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The buffered REST pipeline: the full path a mobile device sees - POST /events -> bounded buffer
 * -> size-or-time flush -> batch insert - plus the two contracts that make it
 * production-grade: bounded event->queryable latency (the flush interval) and
 * 429 backpressure instead of unbounded memory when the sink stalls.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = {"ingest.batch-size=1000", "ingest.flush-interval-ms=500"})
class BufferedRestIngestIntegrationTest extends AbstractClickHouseIntegrationTest {

    @LocalServerPort
    int port;

    @Autowired
    TestRestTemplate rest;

    @Autowired
    JdbcTemplate jdbcTemplate;

    @Autowired
    BenchmarkReporterFactory reporterFactory;

    @Test
    void postedEventsBecomeQueryableWithinTheFlushInterval() throws Exception {
        String marker = "cmp-it3-rest";
        String body = """
                [{"event_type":"page_view","user_id":"u1","session_id":"s1","campaign_id":"%s",
                  "channel":"direct","country":"ID","device_type":"mobile"},
                 {"event_type":"click","user_id":"u2","session_id":"s2","campaign_id":"%s",
                  "channel":"email","source":"newsletter","country":"ID","device_type":"mobile",
                  "event_time":"2026-08-01T03:04:05.678Z"}]""".formatted(marker, marker);

        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        Instant posted = Instant.now();
        ResponseEntity<Map> response = rest.postForEntity(
                "http://localhost:" + port + "/events", new HttpEntity<>(body, headers), Map.class);

        assertThat(response.getStatusCode().value()).isEqualTo(202);
        assertThat(response.getBody().get("accepted")).isEqualTo(2);

        // <2s end-to-end latency is a PLAN success criterion; flush interval is 500ms here.
        long deadline = System.currentTimeMillis() + 5_000;
        long count = 0;
        while (count < 2 && System.currentTimeMillis() < deadline) {
            count = countByCampaign(marker);
            if (count < 2) Thread.sleep(100);
        }
        Duration latency = Duration.between(posted, Instant.now());
        assertThat(count).as("both events queryable").isEqualTo(2);
        assertThat(latency).as("event->queryable latency").isLessThan(Duration.ofSeconds(2));
    }

    @Test
    void benchmarkModeDrainsEverythingThroughTheBuffer() throws Exception {
        long rowsBefore = totalRows();
        long rows = 5_000;

        BufferedIngestService pipeline = new BufferedIngestService(
                new JdbcBatchService(jdbcTemplate, 1_000), 10_000, 1_000, 500);
        BenchmarkReporter reporter = reporterFactory.forRun("rest-it");
        reporter.start();
        long inserted = pipeline.ingest(new SyntheticEventGenerator(rows, 14L), reporter);

        assertThat(inserted).isEqualTo(rows);
        assertThat(reporter.summary().errors()).isZero();
        assertThat(totalRows() - rowsBefore).isEqualTo(rows);
    }

    @Test
    void fullQueueRejectsOffersInsteadOfGrowing() throws Exception {
        CountDownLatch flushGate = new CountDownLatch(1);
        // A sink that stalls until released: the first batch blocks the flusher,
        // then the tiny queue must fill and start rejecting.
        JdbcBatchService stalledWriter = new JdbcBatchService(jdbcTemplate, 10) {
            @Override
            public long flushBatch(List<CampaignEvent> batch, BenchmarkReporter reporter) {
                try {
                    flushGate.await();
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
                return super.flushBatch(batch, reporter);
            }
        };
        BenchmarkReporter reporter = reporterFactory.forRun("rest-backpressure-it");
        reporter.start();

        long accepted = 0;
        boolean sawRejection = false;
        try (EventBuffer buffer = new EventBuffer(stalledWriter, reporter, 5, 10, 50, "it-flusher")) {
            Iterator<CampaignEvent> events = new SyntheticEventGenerator(100, 15L);
            for (int i = 0; i < 100; i++) {
                CampaignEvent e = events.next();
                if (buffer.offer(e)) {
                    accepted++;
                } else {
                    sawRejection = true;
                    Thread.sleep(10); // a client backing off on 429
                }
            }
            assertThat(sawRejection).as("full queue rejects offers").isTrue();
            flushGate.countDown();
        }
        // close() drains: everything accepted was flushed, nothing invented.
        assertThat(reporter.rowsInserted()).isEqualTo(accepted);
    }

    private long countByCampaign(String campaignId) throws Exception {
        try (Connection conn = connect(); Statement stmt = conn.createStatement()) {
            ResultSet rs = stmt.executeQuery(
                    "SELECT count() FROM campaign_events WHERE campaign_id = '" + campaignId + "'");
            rs.next();
            return rs.getLong(1);
        }
    }

    private long totalRows() throws Exception {
        try (Connection conn = connect(); Statement stmt = conn.createStatement()) {
            ResultSet rs = stmt.executeQuery("SELECT count() FROM campaign_events");
            rs.next();
            return rs.getLong(1);
        }
    }
}
