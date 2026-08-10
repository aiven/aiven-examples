package io.aiven.ingest.valkey;

import org.springframework.boot.context.properties.ConfigurationProperties;

import java.net.InetAddress;

/**
 * Valkey Streams buffer settings. The URI comes from the Aiven service
 * (terraform output -raw valkey_uri); rediss:// and valkeys:// both mean TLS.
 *
 * consumer must be unique per app instance (the pod/host name): every instance
 * joins the same consumer group, and Valkey delivers each stream entry to
 * exactly one consumer - N instances = N parallel flushers, no coordination.
 */
@ConfigurationProperties(prefix = "valkey")
public record ValkeyProperties(
        String uri,
        String stream,
        String group,
        String consumer,
        long claimMinIdleMs,
        long maxStreamLength) {

    public ValkeyProperties {
        if (stream == null || stream.isBlank()) stream = "ingest:events";
        if (group == null || group.isBlank()) group = "clickhouse-flushers";
        if (consumer == null || consumer.isBlank()) consumer = defaultConsumerName();
        if (claimMinIdleMs <= 0) claimMinIdleMs = 30_000;
        if (maxStreamLength <= 0) maxStreamLength = 1_000_000;
    }

    /** Lettuce understands rediss:// for TLS; Aiven may hand out valkeys://. */
    public String lettuceUri() {
        return uri.replaceFirst("^valkeys://", "rediss://")
                .replaceFirst("^valkey://", "redis://");
    }

    private static String defaultConsumerName() {
        try {
            return InetAddress.getLocalHost().getHostName();
        } catch (Exception e) {
            return "flusher-" + ProcessHandle.current().pid();
        }
    }
}
