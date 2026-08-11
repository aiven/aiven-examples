package io.aiven.ingest.tier.rest;

import com.fasterxml.jackson.core.JsonFactory;
import com.fasterxml.jackson.core.JsonParser;
import com.fasterxml.jackson.core.JsonToken;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.aiven.ingest.sink.EventSink;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * The REST face of ingestion: what the producer fleet actually calls. Runs on
 * virtual threads (spring.threads.virtual.enabled), so 10k+ concurrent devices
 * cost almost nothing. Events land in the configured EventSink - the
 * in-memory buffer by default, or the Valkey Streams buffer
 * (ingest.buffer=valkey), the durable production architecture.
 *
 * CPU note: this handler deliberately never binds the body to objects. The
 * array is split into its raw element strings with a streaming parser
 * (structural JSON validation only) and handed to the sink - the valkey sink
 * stores the text verbatim, and the flusher, which must parse the JSON anyway
 * to build RowBinary, is where field-level validation lives. On a 2-vCPU
 * container the former databind round-trip (parse to EventDto, re-serialize
 * for XADD) was the single largest per-request CPU cost.
 *
 * Overflow -> 429 + Retry-After: the client SDK retries with backoff, which is
 * exactly the mobile-analytics contract (drop-tolerant, not lossless).
 */
@RestController
public class EventController {

    private static final JsonFactory JSON = new JsonFactory();

    private final EventSink sink;
    private final ObjectMapper mapper;

    public EventController(EventSink sink, ObjectMapper mapper) {
        this.sink = sink;
        this.mapper = mapper;
    }

    @PostMapping(value = "/events", consumes = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<String> ingest(@RequestBody String body) {
        List<String> rawEvents = splitArrayElements(body);
        int accepted = sink.acceptAllRaw(rawEvents, mapper);
        if (accepted < rawEvents.size()) {
            return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
                    .header("Retry-After", "1")
                    .contentType(MediaType.APPLICATION_JSON)
                    .body("{\"accepted\":" + accepted
                            + ",\"rejected\":" + (rawEvents.size() - accepted)
                            + ",\"queue_depth\":" + sink.depth() + "}");
        }
        return ResponseEntity.accepted()
                .contentType(MediaType.APPLICATION_JSON)
                .body("{\"accepted\":" + accepted + "}");
    }

    /**
     * Streaming split of a JSON array into the raw text of its elements.
     * Validates structure (well-formed JSON, top-level array of objects)
     * without building objects; each element's exact source slice is
     * returned.
     */
    private static List<String> splitArrayElements(String body) {
        List<String> elements = new ArrayList<>();
        try (JsonParser parser = JSON.createParser(body)) {
            if (parser.nextToken() != JsonToken.START_ARRAY) {
                throw new IllegalArgumentException("body must be a JSON array of events");
            }
            while (parser.nextToken() == JsonToken.START_OBJECT) {
                long start = parser.currentTokenLocation().getCharOffset();
                parser.skipChildren();
                long end = parser.currentLocation().getCharOffset();
                elements.add(body.substring((int) start, (int) end));
            }
            if (parser.currentToken() != JsonToken.END_ARRAY) {
                throw new IllegalArgumentException("array elements must be JSON objects");
            }
        } catch (java.io.IOException e) {
            throw new IllegalArgumentException("malformed JSON: " + e.getMessage());
        }
        return elements;
    }

    @ExceptionHandler(IllegalArgumentException.class)
    ResponseEntity<Map<String, String>> badRequest(IllegalArgumentException e) {
        return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
    }
}
