package io.aiven.ingest.valkey;

import io.lettuce.core.api.StatefulRedisConnection;
import io.lettuce.core.api.sync.RedisCommands;
import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

/**
 * The buffer's health as gauges, sampled on each metrics export:
 *
 *   valkey.stream.length  - backlog (growing = producers outrun the flushers)
 *   valkey.stream.pending - delivered-not-acked (non-zero in steady state =
 *                           a consumer died, entries await XAUTOCLAIM)
 *
 * Same signals as GET /stats, but on the Grafana dashboard instead of a poll.
 */
@Component
@ConditionalOnProperty(name = "ingest.buffer", havingValue = "valkey")
public class ValkeyStreamMetrics {

    public ValkeyStreamMetrics(MeterRegistry registry,
                               StatefulRedisConnection<String, String> connection,
                               ValkeyProperties props) {
        RedisCommands<String, String> commands = connection.sync();
        Gauge.builder("valkey.stream.length", () -> safe(() -> commands.xlen(props.stream())))
                .description("entries in the ingest stream (backlog)")
                .register(registry);
        Gauge.builder("valkey.stream.pending",
                        () -> safe(() -> commands.xpending(props.stream(), props.group()).getCount()))
                .description("delivered but not yet acknowledged entries")
                .register(registry);
    }

    private static Number safe(java.util.function.Supplier<Number> read) {
        try {
            return read.get();
        } catch (Exception unavailable) {
            // Stream/group not created yet, or Valkey briefly unreachable.
            return 0;
        }
    }
}
