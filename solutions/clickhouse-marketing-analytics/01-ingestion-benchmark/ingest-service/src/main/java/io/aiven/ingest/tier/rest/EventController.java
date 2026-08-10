package io.aiven.ingest.tier.rest;

import io.aiven.ingest.sink.EventSink;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

/**
 * The REST face of ingestion: what the producer fleet actually calls. Runs on
 * virtual threads (spring.threads.virtual.enabled), so 10k+ concurrent devices
 * cost almost nothing. Events land in the configured EventSink - the
 * in-memory buffer by default, or the Valkey Streams buffer
 * (ingest.buffer=valkey), the durable production architecture.
 * Overflow -> 429 + Retry-After: the client SDK retries with backoff, which is
 * exactly the mobile-analytics contract (drop-tolerant, not lossless).
 */
@RestController
public class EventController {

    private final EventSink sink;

    public EventController(EventSink sink) {
        this.sink = sink;
    }

    @PostMapping("/events")
    public ResponseEntity<Map<String, Object>> ingest(@RequestBody List<EventDto> events) {
        int accepted = sink.acceptAll(events);
        if (accepted < events.size()) {
            return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
                    .header("Retry-After", "1")
                    .body(Map.of("accepted", accepted,
                            "rejected", events.size() - accepted,
                            "queue_depth", sink.depth()));
        }
        return ResponseEntity.accepted().body(Map.of("accepted", accepted));
    }
}
