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


import static org.assertj.core.api.Assertions.assertThat;

/**
 * The public-deploy contract: with ingest.api-key set, everything except the
 * platform's health probe requires the X-API-Key header. (The other suites run
 * without a key and prove the filter stays a no-op for local/CLI use.)
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "ingest.api-key=it-secret")
class ApiKeySecurityIntegrationTest extends AbstractClickHouseIntegrationTest {

    @LocalServerPort
    int port;

    @Autowired
    TestRestTemplate rest;

    @Test
    void protectedEndpointsRejectMissingOrWrongKey() {
        assertThat(get("/benchmarks", null).getStatusCode().value()).isEqualTo(401);
        assertThat(get("/benchmarks", "wrong-key").getStatusCode().value()).isEqualTo(401);
        assertThat(post("/events", "[]", null).getStatusCode().value()).isEqualTo(401);
        assertThat(get("/actuator/metrics", null).getStatusCode().value()).isEqualTo(401);
    }

    @Test
    void correctKeyPassesThrough() {
        assertThat(get("/benchmarks", "it-secret").getStatusCode().value()).isEqualTo(200);
        assertThat(post("/events", "[]", "it-secret").getStatusCode().value()).isEqualTo(202);
    }

    @Test
    void healthProbeStaysOpenForThePlatform() {
        assertThat(get("/actuator/health", null).getStatusCode().value()).isEqualTo(200);
    }

    private ResponseEntity<String> get(String path, String key) {
        return rest.exchange("http://localhost:" + port + path, HttpMethod.GET,
                new HttpEntity<>(headers(key)), String.class);
    }

    private ResponseEntity<String> post(String path, String body, String key) {
        HttpHeaders h = headers(key);
        h.setContentType(MediaType.APPLICATION_JSON);
        return rest.postForEntity("http://localhost:" + port + path,
                new HttpEntity<>(body, h), String.class);
    }

    private HttpHeaders headers(String key) {
        HttpHeaders h = new HttpHeaders();
        if (key != null) {
            h.set("X-API-Key", key);
        }
        return h;
    }
}
