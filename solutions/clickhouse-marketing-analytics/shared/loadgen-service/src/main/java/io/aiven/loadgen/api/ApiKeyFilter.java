package io.aiven.loadgen.api;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

/**
 * Same contract as the ingest service's filter: when loadgen.api-key is set,
 * every endpoint except the health probe requires it in X-API-Key
 * (constant-time compared). A load generator IS a DoS tool - never expose it
 * publicly without a key.
 */
@Component
public class ApiKeyFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(ApiKeyFilter.class);
    static final String HEADER = "X-API-Key";

    private final byte[] expectedKey;

    public ApiKeyFilter(@Value("${loadgen.api-key:}") String apiKey) {
        this.expectedKey = apiKey == null || apiKey.isBlank()
                ? null
                : apiKey.getBytes(StandardCharsets.UTF_8);
        if (expectedKey == null) {
            log.warn("loadgen.api-key is NOT set - /loadtests is open to anyone who can reach "
                    + "this host. Set LOADGEN_API_KEY before exposing the service publicly.");
        }
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
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
