package io.aiven.ingest.tier.rest;

import com.fasterxml.jackson.core.JsonFactory;
import com.fasterxml.jackson.core.JsonParser;
import com.fasterxml.jackson.core.JsonToken;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.aiven.ingest.sink.EventSink;
import jakarta.servlet.http.HttpServlet;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.boot.web.servlet.ServletRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * POST /events as a PLAIN servlet, registered beside Spring MVC rather than
 * inside it. The control-plane endpoints (/benchmarks, /config, /stats) stay
 * on MVC where its conveniences earn their cost; the hot path skips the
 * DispatcherServlet entirely - no handler mapping, no argument resolution,
 * no return-value handling - because at thousands of requests per second on
 * a 2-vCPU container that machinery is measurable per-request CPU.
 *
 * The body is processed as bytes end to end: a streaming parser slices the
 * JSON array into its raw element byte ranges (structural validation only,
 * no object binding, no charset decode), and the sink writes those bytes
 * verbatim. Field-level validation lives in the flusher, which parses the
 * JSON anyway.
 *
 * Security and virtual threads are unchanged: ApiKeyFilter is a Spring bean
 * filter applied to ALL servlets, and Tomcat executes every servlet on
 * virtual threads via spring.threads.virtual.enabled.
 */
public class EventIngestServlet extends HttpServlet {

    private static final JsonFactory JSON = new JsonFactory();

    private final transient EventSink sink;
    private final transient ObjectMapper mapper;

    public EventIngestServlet(EventSink sink, ObjectMapper mapper) {
        this.sink = sink;
        this.mapper = mapper;
    }

    @Override
    protected void doPost(HttpServletRequest request, HttpServletResponse response) throws IOException {
        byte[] body = request.getInputStream().readAllBytes();
        List<byte[]> rawEvents;
        try {
            rawEvents = splitArrayElements(body);
        } catch (IllegalArgumentException bad) {
            respond(response, 400, "{\"error\":\"" + bad.getMessage().replace('"', '\'') + "\"}");
            return;
        }
        int accepted;
        try {
            accepted = sink.acceptAllRaw(rawEvents, mapper);
        } catch (IllegalArgumentException bad) {
            respond(response, 400, "{\"error\":\"" + bad.getMessage().replace('"', '\'') + "\"}");
            return;
        }
        if (accepted < rawEvents.size()) {
            response.setHeader("Retry-After", "1");
            respond(response, 429, "{\"accepted\":" + accepted
                    + ",\"rejected\":" + (rawEvents.size() - accepted)
                    + ",\"queue_depth\":" + sink.depth() + "}");
            return;
        }
        respond(response, 202, "{\"accepted\":" + accepted + "}");
    }

    private static void respond(HttpServletResponse response, int status, String json) throws IOException {
        response.setStatus(status);
        response.setContentType("application/json");
        response.getOutputStream().write(json.getBytes(StandardCharsets.UTF_8));
    }

    /**
     * Streaming split of a JSON array into the raw BYTES of its elements:
     * well-formedness and top-level structure are validated, nothing is
     * decoded or bound.
     */
    private static List<byte[]> splitArrayElements(byte[] body) {
        List<byte[]> elements = new ArrayList<>();
        try (JsonParser parser = JSON.createParser(body)) {
            if (parser.nextToken() != JsonToken.START_ARRAY) {
                throw new IllegalArgumentException("body must be a JSON array of events");
            }
            while (parser.nextToken() == JsonToken.START_OBJECT) {
                long start = parser.currentTokenLocation().getByteOffset();
                parser.skipChildren();
                long end = parser.currentLocation().getByteOffset();
                elements.add(Arrays.copyOfRange(body, (int) start, (int) end));
            }
            if (parser.currentToken() != JsonToken.END_ARRAY) {
                throw new IllegalArgumentException("array elements must be JSON objects");
            }
        } catch (IOException e) {
            throw new IllegalArgumentException("malformed JSON: " + e.getMessage());
        }
        return elements;
    }

    @Configuration
    public static class Registration {
        @Bean
        public ServletRegistrationBean<EventIngestServlet> eventIngestServlet(
                EventSink sink, ObjectMapper mapper) {
            var bean = new ServletRegistrationBean<>(new EventIngestServlet(sink, mapper), "/events");
            bean.setLoadOnStartup(1);
            return bean;
        }
    }
}
