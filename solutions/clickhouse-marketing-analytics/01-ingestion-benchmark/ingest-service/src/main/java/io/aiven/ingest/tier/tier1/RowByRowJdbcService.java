package io.aiven.ingest.tier.tier1;

import io.aiven.ingest.bench.BenchmarkReporter;
import io.aiven.ingest.model.CampaignEvent;
import io.aiven.ingest.tier.IngestTier;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.sql.Timestamp;
import java.util.Iterator;

/**
 * Tier 1 - the baseline: the customer's original pattern, one jdbcTemplate.update()
 * per event. Each call is one HTTP round-trip and one INSERT query, so
 * throughput is capped at ~1/RTT per thread, and every insert creates its own
 * part - watch system.parts explode (shared/schema/03_diagnostics.sql) and expect
 * TOO_MANY_PARTS / merge throttling on sustained runs. That is the point:
 * reproduce the pain before fixing it.
 */
@Service
public class RowByRowJdbcService implements IngestTier {

    public static final String INSERT_SQL = """
            INSERT INTO campaign_events
            (event_time, event_type, user_id, session_id, campaign_id, channel,
             source, medium, ad_group, keyword, landing_page, conversion_value,
             currency, country, device_type, properties)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""";

    private final JdbcTemplate jdbcTemplate;

    public RowByRowJdbcService(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    @Override
    public int tier() {
        return 1;
    }

    @Override
    public String description() {
        return "row-by-row JDBC (the original customer code, baseline)";
    }

    @Override
    public long ingest(Iterator<CampaignEvent> events, BenchmarkReporter reporter) {
        long inserted = 0;
        while (events.hasNext()) {
            CampaignEvent e = events.next();
            long t0 = System.nanoTime();
            try {
                jdbcTemplate.update(INSERT_SQL,
                        Timestamp.from(e.eventTime()), e.eventType(), e.userId(), e.sessionId(),
                        e.campaignId(), e.channel(), e.source(), e.medium(), e.adGroup(),
                        e.keyword(), e.landingPage(), e.conversionValue(), e.currency(),
                        e.country(), e.deviceType(), e.properties());
                reporter.recordFlush(1, System.nanoTime() - t0);
                inserted++;
            } catch (RuntimeException ex) {
                reporter.recordError(ex);
            }
        }
        return inserted;
    }
}
