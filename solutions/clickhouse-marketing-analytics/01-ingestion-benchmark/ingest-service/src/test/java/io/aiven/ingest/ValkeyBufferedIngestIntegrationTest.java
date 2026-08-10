package io.aiven.ingest;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.testcontainers.containers.GenericContainer;
import org.testcontainers.utility.DockerImageName;

import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.Statement;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The post-ladder production architecture end to end: POST /events -> XADD to
 * a real Valkey stream -> in-app flusher (consumer group) -> native-client
 * bulk insert -> queryable in ClickHouse. Plus the runtime-tunable batch
 * geometry: GET/PUT /config against the ingest:config hash, bounds-checked.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = {
                "ingest.buffer=valkey",
                "ingest.batch-size=1000",
                "ingest.flush-interval-ms=300",
                "valkey.consumer=it-flusher",
                "valkey.claim-min-idle-ms=1000"
        })
class ValkeyBufferedIngestIntegrationTest extends AbstractClickHouseIntegrationTest {

    static final GenericContainer<?> VALKEY = new GenericContainer<>(
            DockerImageName.parse("valkey/valkey:9.1"))
            .withExposedPorts(6379);

    static {
        VALKEY.start();
    }

    @DynamicPropertySource
    static void valkeyProperties(DynamicPropertyRegistry registry) {
        registry.add("valkey.uri",
                () -> "redis://" + VALKEY.getHost() + ":" + VALKEY.getMappedPort(6379));
    }

    @LocalServerPort
    int port;

    @Autowired
    TestRestTemplate rest;

    @Test
    void postedEventsFlowThroughValkeyIntoClickHouse() throws Exception {
        String marker = "cmp-it-valkey";
        String body = """
                [{"event_type":"page_view","user_id":"u1","session_id":"s1","campaign_id":"%s",
                  "channel":"direct","country":"ID","device_type":"mobile"},
                 {"event_type":"purchase","user_id":"u2","session_id":"s2","campaign_id":"%s",
                  "channel":"email","source":"newsletter","conversion_value":12.5,"currency":"USD",
                  "country":"ID","device_type":"mobile","event_time":"2026-08-01T03:04:05.678Z"}]"""
                .formatted(marker, marker);

        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        Instant posted = Instant.now();
        ResponseEntity<Map> response = rest.postForEntity(
                url("/events"), new HttpEntity<>(body, headers), Map.class);

        assertThat(response.getStatusCode().value()).isEqualTo(202);
        assertThat(response.getBody().get("accepted")).isEqualTo(2);

        // Same contract as the in-memory tier: bounded event->queryable
        // latency, here flush-interval 300ms + one insert round trip.
        long deadline = System.currentTimeMillis() + 10_000;
        long count = 0;
        while (count < 2 && System.currentTimeMillis() < deadline) {
            count = countByCampaign(marker);
            if (count < 2) Thread.sleep(100);
        }
        Duration latency = Duration.between(posted, Instant.now());
        assertThat(count).as("both events queryable via the Valkey path").isEqualTo(2);
        assertThat(latency).as("event->queryable latency").isLessThan(Duration.ofSeconds(5));

        // The mini-benchmark's observation point: flushed counters move,
        // nothing is stuck pending after a clean flush.
        Map stats = rest.getForEntity(url("/stats"), Map.class).getBody();
        assertThat(stats.get("mode")).isEqualTo("valkey");
        Map flusher = (Map) stats.get("flusher");
        assertThat(((Number) flusher.get("rows_flushed")).longValue()).isGreaterThanOrEqualTo(2);
        assertThat(((Number) flusher.get("errors")).longValue()).isZero();
        Map stream = (Map) stats.get("stream");
        assertThat(((Number) stream.get("pending")).longValue()).isZero();
    }

    @Test
    void configRoundTripRetunesTheFlusher() {
        ResponseEntity<Map> initial = rest.getForEntity(url("/config"), Map.class);
        assertThat(initial.getStatusCode().value()).isEqualTo(200);
        assertThat(initial.getBody()).containsKeys("batch_size", "flush_interval_ms");

        ResponseEntity<Map> updated = putConfig("{\"batch_size\": 50000, \"flush_interval_ms\": 900}");
        assertThat(updated.getStatusCode().value()).isEqualTo(200);
        assertThat(updated.getBody().get("batch_size")).isEqualTo(50_000);
        assertThat(updated.getBody().get("flush_interval_ms")).isEqualTo(900);

        // The hash in Valkey is the source of truth: a fresh GET reflects it.
        ResponseEntity<Map> after = rest.getForEntity(url("/config"), Map.class);
        assertThat(after.getBody().get("batch_size")).isEqualTo(50_000);

        // Partial update keeps the other knob.
        ResponseEntity<Map> partial = putConfig("{\"flush_interval_ms\": 400}");
        assertThat(partial.getBody().get("batch_size")).isEqualTo(50_000);
        assertThat(partial.getBody().get("flush_interval_ms")).isEqualTo(400);
    }

    @Test
    void nonsenseConfigIsRejectedAndChangesNothing() {
        Map before = rest.getForEntity(url("/config"), Map.class).getBody();

        assertThat(putConfig("{\"batch_size\": 1}").getStatusCode().value()).isEqualTo(400);
        assertThat(putConfig("{\"flush_interval_ms\": 999999}").getStatusCode().value()).isEqualTo(400);
        assertThat(putConfig("{}").getStatusCode().value()).isEqualTo(400);

        Map after = rest.getForEntity(url("/config"), Map.class).getBody();
        assertThat(after).isEqualTo(before);
    }

    private ResponseEntity<Map> putConfig(String json) {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        return rest.exchange(url("/config"), HttpMethod.PUT,
                new HttpEntity<>(json, headers), Map.class);
    }

    private String url(String path) {
        return "http://localhost:" + port + path;
    }

    private long countByCampaign(String campaignId) throws Exception {
        try (Connection conn = connect(); Statement stmt = conn.createStatement()) {
            ResultSet rs = stmt.executeQuery(
                    "SELECT count() FROM campaign_events WHERE campaign_id = '" + campaignId + "'");
            rs.next();
            return rs.getLong(1);
        }
    }
}
