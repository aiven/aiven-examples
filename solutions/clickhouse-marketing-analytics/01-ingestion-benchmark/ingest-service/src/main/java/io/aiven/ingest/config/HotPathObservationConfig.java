package io.aiven.ingest.config;

import io.micrometer.observation.ObservationPredicate;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.server.observation.ServerRequestObservationContext;

/**
 * /events pays for no per-request observation: at thousands of req/s the
 * http.server.requests timer's tag allocation is measurable CPU, the hot
 * path has better signals (ingest.rows, valkey.stream.*, the loadgen's own
 * counters), and under ingress connection churn that timer measured orphaned
 * half-read requests rather than real work anyway.
 */
@Configuration
public class HotPathObservationConfig {

    @Bean
    ObservationPredicate skipEventsHttpObservation() {
        return (name, context) ->
                !("http.server.requests".equals(name)
                        && context instanceof ServerRequestObservationContext http
                        && "/events".equals(http.getCarrier().getRequestURI()));
    }
}
