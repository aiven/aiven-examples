package io.aiven.ingest.api;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Arrays;

/**
 * Shared-secret auth for the public-facing deploy (Aiven Apps exposes the app
 * on the internet): when ingest.api-key is set, every request must carry it in
 * an X-API-Key header - except the health endpoints the platform probes.
 * Comparison is constant-time.
 *
 * When the key is unset the filter is a no-op (local dev, tests, CLI runs) -
 * but running the aiven profile without one logs a loud warning at startup.
 */
@Component
public class ApiKeyFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(ApiKeyFilter.class);
    static final String HEADER = "X-API-Key";

    private final byte[] expectedKey;

    public ApiKeyFilter(@Value("${ingest.api-key:}") String apiKey, Environment env) {
        this.expectedKey = apiKey == null || apiKey.isBlank()
                ? null
                : apiKey.getBytes(StandardCharsets.UTF_8);
        if (expectedKey == null && Arrays.asList(env.getActiveProfiles()).contains("aiven")) {
            log.warn("ingest.api-key is NOT set while running the aiven profile - "
                    + "/benchmarks and /events are open to anyone who can reach this host. "
                    + "Set INGEST_API_KEY before exposing the service publicly.");
        }
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        // Health stays open: Aiven Apps probes it without headers.
        return expectedKey == null || request.getRequestURI().startsWith("/actuator/health");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {
        String presented = request.getHeader(HEADER);
        if (presented != null && MessageDigest.isEqual(
                expectedKey, presented.getBytes(StandardCharsets.UTF_8))) {
            chain.doFilter(request, response);
            return;
        }
        response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
        response.setContentType("application/json");
        response.getWriter().write("{\"error\":\"missing or invalid " + HEADER + " header\"}");
    }
}
