package io.aiven.loadgen.run;

import java.time.Instant;
import java.util.concurrent.ThreadLocalRandom;

/**
 * Synthesizes campaign_events JSON payloads, mirroring the k6 script's
 * randomEvent() (shared/loadgen/k6-events.js) so both drivers produce the
 * same event shape. Plain string building: at 100k events/s the factory must
 * never be the bottleneck.
 */
final class EventFactory {

    private static final String[] CHANNELS = {"paid_search", "organic", "email", "social", "direct"};
    private static final String[] EVENT_TYPES = {"page_view", "page_view", "page_view", "click", "click", "lead", "purchase"};
    private static final String[] DEVICES = {"mobile", "mobile", "mobile", "desktop", "tablet"};

    private EventFactory() {
    }

    /** One JSON array body of {@code batchSize} events for POST /events. */
    static String batchBody(int userId, long iteration, int batchSize) {
        StringBuilder sb = new StringBuilder(batchSize * 320).append('[');
        for (int i = 0; i < batchSize; i++) {
            if (i > 0) sb.append(',');
            appendEvent(sb, userId, iteration);
        }
        return sb.append(']').toString();
    }

    private static void appendEvent(StringBuilder sb, int userId, long iteration) {
        ThreadLocalRandom rnd = ThreadLocalRandom.current();
        String eventType = EVENT_TYPES[rnd.nextInt(EVENT_TYPES.length)];
        boolean purchase = "purchase".equals(eventType);
        sb.append("{\"event_time\":\"").append(Instant.now()).append('"')
                .append(",\"event_type\":\"").append(eventType).append('"')
                .append(",\"user_id\":\"u").append(userId).append('"')
                .append(",\"session_id\":\"s").append(userId).append('-').append(iteration).append('"')
                .append(",\"campaign_id\":\"cmp-").append(String.format("%03d", rnd.nextInt(200))).append('"')
                .append(",\"channel\":\"").append(CHANNELS[rnd.nextInt(CHANNELS.length)]).append('"')
                .append(",\"country\":\"ID\"")
                .append(",\"device_type\":\"").append(DEVICES[rnd.nextInt(DEVICES.length)]).append('"');
        if (purchase) {
            sb.append(",\"conversion_value\":").append(Math.round(150_000 * Math.exp(rnd.nextDouble() * 2 - 1)))
                    .append(",\"currency\":\"IDR\"");
        }
        sb.append(",\"properties\":\"{\\\"app_version\\\":\\\"5.4\\\",\\\"ab_variant\\\":\\\"")
                .append(rnd.nextBoolean() ? 'A' : 'B').append("\\\"}\"}");
    }
}
