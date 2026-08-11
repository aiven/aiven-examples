package io.aiven.loadgen;

import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;

import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.concurrent.atomic.AtomicLong;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Drives a short firehose and a devices run against a stub /events endpoint,
 * asserting the control API contract (202/busy-409/400/404) and that the
 * counters add up: every event the stub accepted must be accounted for.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class LoadTestIntegrationTest {

    static HttpServer stub;
    static final AtomicLong stubEventsSeen = new AtomicLong();

    @BeforeAll
    static void startStub() throws Exception {
        stub = HttpServer.create(new InetSocketAddress(0), 0);
        stub.createContext("/events", exchange -> {
            String body = new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8);
            // Count events without a JSON parser: one event_type per event.
            Matcher m = Pattern.compile("\"event_type\"").matcher(body);
            long events = 0;
            while (m.find()) events++;
            stubEventsSeen.addAndGet(events);
            byte[] response = "{\"accepted\":%d}".formatted(events).getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().add("Content-Type", "application/json");
            exchange.sendResponseHeaders(202, response.length);
            try (OutputStream os = exchange.getResponseBody()) {
                os.write(response);
            }
        });
        stub.setExecutor(java.util.concurrent.Executors.newVirtualThreadPerTaskExecutor());
        stub.start();
    }

    @AfterAll
    static void stopStub() {
        stub.stop(0);
    }

    @LocalServerPort
    int port;

    @Autowired
    TestRestTemplate rest;

    @Test
    void firehoseRunDeliversThePacedRateAndCountersAddUp() throws Exception {
        long seenBefore = stubEventsSeen.get();
        ResponseEntity<Map> started = post(
                "{\"mode\":\"firehose\",\"rate\":2000,\"duration_s\":3,\"target_url\":\"" + stubUrl() + "\"}");
        assertThat(started.getStatusCode().value()).isEqualTo(202);
        String id = (String) started.getBody().get("id");
        assertThat(id).startsWith("load-").endsWith("-firehose");

        // A second run while busy must 409 with the active run's id.
        ResponseEntity<Map> busy = post(
                "{\"mode\":\"firehose\",\"rate\":10,\"duration_s\":1,\"target_url\":\"" + stubUrl() + "\"}");
        assertThat(busy.getStatusCode().value()).isEqualTo(409);
        assertThat(busy.getBody().get("id")).isEqualTo(id);

        Map<String, Object> result = pollUntilDone(id);
        assertThat(result.get("state")).isEqualTo("COMPLETED");
        long accepted = ((Number) result.get("events_accepted")).longValue();
        // Paced at 2000/s for 3s = 6000 nominal. A cold JVM on a shared CI
        // box under-paces; what matters here is that pacing works at all and
        // never overshoots. Rate FIDELITY is asserted by the local validation
        // run, not this smoke test.
        assertThat(accepted).isBetween(2_000L, 6_100L);
        assertThat(((Number) result.get("request_errors")).longValue()).isZero();
        assertThat(stubEventsSeen.get() - seenBefore).isEqualTo(accepted);
        Map<?, ?> latency = (Map<?, ?>) result.get("request_latency_ms");
        assertThat(latency.get("p50")).isNotNull();
        assertThat(latency.get("p99")).isNotNull();
    }

    @Test
    void devicesRunSimulatesTheFleet() throws Exception {
        ResponseEntity<Map> started = post(
                "{\"mode\":\"devices\",\"users\":50,\"duration_s\":3,\"target_url\":\"" + stubUrl() + "\"}");
        assertThat(started.getStatusCode().value()).isEqualTo(202);
        Map<String, Object> result = pollUntilDone((String) started.getBody().get("id"));
        assertThat(result.get("state")).isEqualTo("COMPLETED");
        // 50 devices, 1-5 events, ~1 upload each in 3s (2-6s think time): >= 50 events.
        assertThat(((Number) result.get("events_accepted")).longValue()).isGreaterThanOrEqualTo(50);
        assertThat(((Number) result.get("request_errors")).longValue()).isZero();
    }

    @Test
    void rejectsBadInputAndUnknownIds() {
        assertThat(post("{\"rate\":100}").getStatusCode().value()).as("missing mode").isEqualTo(400);
        assertThat(post("{\"mode\":\"warp\"}").getStatusCode().value()).as("unknown mode").isEqualTo(400);
        assertThat(post("{\"mode\":\"firehose\",\"rate\":0}").getStatusCode().value()).as("bad rate").isEqualTo(400);
        assertThat(rest.getForEntity(url("/loadtests/load-999-firehose"), Map.class)
                .getStatusCode().value()).isEqualTo(404);
    }

    private Map<String, Object> pollUntilDone(String id) throws InterruptedException {
        long deadline = System.currentTimeMillis() + 30_000;
        while (System.currentTimeMillis() < deadline) {
            Map<String, Object> status = rest.getForEntity(url("/loadtests/" + id), Map.class).getBody();
            if (!"RUNNING".equals(status.get("state"))) {
                return status;
            }
            Thread.sleep(200);
        }
        throw new AssertionError("load test " + id + " did not finish in time");
    }

    private ResponseEntity<Map> post(String body) {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        return rest.postForEntity(url("/loadtests"), new HttpEntity<>(body, headers), Map.class);
    }

    private String url(String path) {
        return "http://localhost:" + port + path;
    }

    private static String stubUrl() {
        return "http://localhost:" + stub.getAddress().getPort();
    }
}
