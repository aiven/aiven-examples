package io.aiven.ingest.valkey;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * Admin API over the ingest:config hash. One PUT retunes every flusher on
 * every app instance on its next cycle:
 *
 *   GET  /config
 *   PUT  /config   {"batch_size": 50000, "flush_interval_ms": 1000}
 *
 * Values are bounds-checked (IngestTuning); nonsense gets a 400 and changes
 * nothing. Protected by the same X-API-Key filter as the rest of the service.
 */
@RestController
@ConditionalOnProperty(name = "ingest.buffer", havingValue = "valkey")
public class ConfigController {

    private final IngestConfigStore store;

    public ConfigController(IngestConfigStore store) {
        this.store = store;
    }

    @GetMapping("/config")
    public Map<String, Object> get() {
        return toBody(store.current());
    }

    @PutMapping("/config")
    public ResponseEntity<Map<String, Object>> put(@RequestBody Map<String, Object> body) {
        try {
            Integer batchSize = intField(body, "batch_size");
            Long flushIntervalMs = longField(body, "flush_interval_ms");
            if (batchSize == null && flushIntervalMs == null) {
                return ResponseEntity.badRequest().body(Map.of(
                        "error", "nothing to update: send batch_size and/or flush_interval_ms"));
            }
            return ResponseEntity.ok(toBody(store.update(batchSize, flushIntervalMs)));
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        }
    }

    private static Map<String, Object> toBody(IngestTuning tuning) {
        return Map.of(
                "batch_size", tuning.batchSize(),
                "flush_interval_ms", tuning.flushIntervalMs());
    }

    private static Integer intField(Map<String, Object> body, String name) {
        Object v = body.get(name);
        if (v == null) return null;
        if (v instanceof Number n) return n.intValue();
        throw new IllegalArgumentException(name + " must be a number, got: " + v);
    }

    private static Long longField(Map<String, Object> body, String name) {
        Object v = body.get(name);
        if (v == null) return null;
        if (v instanceof Number n) return n.longValue();
        throw new IllegalArgumentException(name + " must be a number, got: " + v);
    }
}
