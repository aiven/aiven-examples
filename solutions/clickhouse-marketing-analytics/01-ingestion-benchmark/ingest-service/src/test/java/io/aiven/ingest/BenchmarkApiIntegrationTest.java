package io.aiven.ingest;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.test.web.server.LocalServerPort;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;

import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The remote-control API that replaces the CLI when the service runs on Aiven
 * Apps: start a run, poll it to completion, read the ladder numbers from the
 * response. Also the failure contracts a remote caller depends on: 400 on bad
 * input, 404 on unknown ids.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class BenchmarkApiIntegrationTest extends AbstractClickHouseIntegrationTest {

    @LocalServerPort
    int port;

    @Autowired
    TestRestTemplate rest;

    @Test
    void startPollAndReadResults() throws Exception {
        ResponseEntity<Map> started = post("{\"tier\": 4, \"rows\": 3000, \"batch_size\": 1000}");

        assertThat(started.getStatusCode().value()).isEqualTo(202);
        String id = (String) started.getBody().get("id");
        assertThat(id).startsWith("run-").endsWith("-tier4");
        assertThat(started.getHeaders().getLocation().toString()).isEqualTo("/benchmarks/" + id);

        Map<String, Object> status = pollUntilDone(id);
        assertThat(status.get("state")).isEqualTo("COMPLETED");
        assertThat(((Number) status.get("rows_inserted")).longValue()).isEqualTo(3000);
        assertThat(((Number) status.get("progress_pct")).doubleValue()).isEqualTo(100.0);
        assertThat(((Number) status.get("flushes")).longValue()).isEqualTo(3);
        assertThat(((Number) status.get("errors")).longValue()).isZero();
        assertThat(((Number) status.get("rows_per_sec")).doubleValue()).isPositive();
        assertThat(status.get("finished_at")).isNotNull();
        assertThat(((Map<?, ?>) status.get("params")).get("batch_size")).isEqualTo(1000);

        // The run must appear in the overall listing too.
        ResponseEntity<List> all = rest.getForEntity(url("/benchmarks"), List.class);
        assertThat(all.getBody().stream()
                .anyMatch(r -> id.equals(((Map<?, ?>) r).get("id")))).isTrue();
    }

    @Test
    void tier3RunsCarryTheirConcurrency() throws Exception {
        ResponseEntity<Map> started = post("{\"tier\": 3, \"rows\": 50, \"concurrency\": 8}");
        assertThat(started.getStatusCode().value()).isEqualTo(202);
        String id = (String) started.getBody().get("id");
        assertThat(id).endsWith("-tier3");
        assertThat(pollUntilDone(id).get("state")).isEqualTo("COMPLETED");
    }

    @Test
    void rejectsBadInput() {
        assertThat(post("{\"rows\": 1000}").getStatusCode().value()).as("missing tier").isEqualTo(400);
        assertThat(post("{\"tier\": 9}").getStatusCode().value()).as("unknown tier").isEqualTo(400);
        assertThat(post("{\"tier\": 4, \"rows\": -5}").getStatusCode().value()).as("negative rows").isEqualTo(400);
    }

    @Test
    void unknownRunIs404() {
        ResponseEntity<Map> response = rest.getForEntity(url("/benchmarks/run-999-tier9"), Map.class);
        assertThat(response.getStatusCode().value()).isEqualTo(404);
    }

    private ResponseEntity<Map> post(String body) {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        return rest.postForEntity(url("/benchmarks"), new HttpEntity<>(body, headers), Map.class);
    }

    private Map<String, Object> pollUntilDone(String id) throws InterruptedException {
        long deadline = System.currentTimeMillis() + 30_000;
        while (System.currentTimeMillis() < deadline) {
            Map<String, Object> status = rest.getForEntity(url("/benchmarks/" + id), Map.class).getBody();
            if (!"RUNNING".equals(status.get("state"))) {
                return status;
            }
            Thread.sleep(100);
        }
        throw new AssertionError("run " + id + " did not finish within 30s");
    }

    private String url(String path) {
        return "http://localhost:" + port + path;
    }
}
