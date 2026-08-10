package io.aiven.ingest.generator;

import io.aiven.ingest.model.CampaignEvent;

import java.time.Instant;
import java.util.Iterator;
import java.util.Locale;
import java.util.random.RandomGenerator;
import java.util.random.RandomGeneratorFactory;

/**
 * Benchmark payload generator: deterministic-seed synthetic campaign_events with
 * realistic column shapes (channel mix, ID-weighted countries, ~75% mobile,
 * log-normal IDR conversion values on purchases). This exists so every tier
 * benchmarks the same byte-for-byte payload; the journey-based generator that
 * makes the 7 dashboard queries meaningful is shared/datagen/.
 */
public final class SyntheticEventGenerator implements Iterator<CampaignEvent> {

    private static final String[] CHANNELS = {"paid_search", "organic", "email", "social", "direct"};
    private static final double[] CHANNEL_W = {0.30, 0.25, 0.20, 0.15, 0.10};
    private static final String[] EVENT_TYPES = {
            "page_view", "click", "email_send", "email_open", "email_click",
            "lead", "trial_start", "purchase", "unsubscribe", "bounce"};
    private static final double[] EVENT_W = {0.55, 0.20, 0.10, 0.06, 0.025, 0.03, 0.015, 0.01, 0.007, 0.003};
    private static final String[] COUNTRIES = {"ID", "ID", "ID", "ID", "ID", "ID", "ID", "SG", "MY", "PH"};
    private static final String[] DEVICES = {"mobile", "mobile", "mobile", "desktop", "tablet"};
    private static final String[] SOURCES = {"google", "facebook", "instagram", "tiktok", "newsletter", "direct"};
    private static final String[] MEDIUMS = {"cpc", "organic", "email", "social", "none"};

    private final RandomGenerator rnd;
    private final long total;
    private long emitted;

    public SyntheticEventGenerator(long total, long seed) {
        this.total = total;
        this.rnd = RandomGeneratorFactory.of("L64X128MixRandom").create(seed);
    }

    @Override
    public boolean hasNext() {
        return emitted < total;
    }

    @Override
    public CampaignEvent next() {
        emitted++;
        String channel = pick(CHANNELS, CHANNEL_W);
        String eventType = pick(EVENT_TYPES, EVENT_W);
        boolean paidSearch = "paid_search".equals(channel);
        boolean purchase = "purchase".equals(eventType);
        long userNo = (long) (Math.pow(rnd.nextDouble(), 2.5) * 3_000_000); // power-law-ish user activity
        int campaignNo = rnd.nextInt(200);
        // Log-normal, IDR scale: median ~150k with a heavy tail.
        Double value = purchase ? Math.round(Math.exp(11.9 + 0.9 * rnd.nextGaussian())) * 1.0 : null;
        return new CampaignEvent(
                Instant.now(),
                eventType,
                "u" + userNo,
                "s" + userNo + "-" + rnd.nextInt(1000),
                String.format(Locale.ROOT, "cmp-%03d", campaignNo),
                channel,
                SOURCES[rnd.nextInt(SOURCES.length)],
                MEDIUMS[rnd.nextInt(MEDIUMS.length)],
                paidSearch ? "ag-" + rnd.nextInt(8) : null,
                paidSearch ? "kw-" + rnd.nextInt(50) : null,
                "/lp/" + rnd.nextInt(30),
                value,
                purchase ? "IDR" : null,
                COUNTRIES[rnd.nextInt(COUNTRIES.length)],
                DEVICES[rnd.nextInt(DEVICES.length)],
                "{\"app_version\":\"" + (5 + rnd.nextInt(3)) + "." + rnd.nextInt(10)
                        + "\",\"ab_variant\":\"" + (rnd.nextBoolean() ? "A" : "B") + "\"}");
    }

    private String pick(String[] values, double[] weights) {
        double r = rnd.nextDouble(), acc = 0;
        for (int i = 0; i < values.length; i++) {
            acc += weights[i];
            if (r < acc) return values[i];
        }
        return values[values.length - 1];
    }
}
