package io.aiven.ingest.tier.tier4;

import io.aiven.ingest.bench.BenchmarkReporter;
import io.aiven.ingest.model.CampaignEvent;
import io.aiven.ingest.tier.IngestTier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.jdbc.core.BatchPreparedStatementSetter;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.sql.Timestamp;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;

/**
 * Tier 4 - jdbcTemplate.batchUpdate() with 10k-50k rows per batch (the "keep
 * your current stack, change 20 lines" option). One batch = one INSERT = one
 * part, so merges keep up and the rollup MV executes once per batch instead of
 * once per row. Compare 10k vs 50k with --batch-size.
 */
@Service
public class JdbcBatchService implements IngestTier {

    static final String INSERT_SQL = """
            INSERT INTO campaign_events
            (event_time, event_type, user_id, session_id, campaign_id, channel,
             source, medium, ad_group, keyword, landing_page, conversion_value,
             currency, country, device_type, properties)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""";

    private final JdbcTemplate jdbcTemplate;
    private final int batchSize;

    public JdbcBatchService(JdbcTemplate jdbcTemplate,
                            @Value("${ingest.batch-size:10000}") int batchSize) {
        this.jdbcTemplate = jdbcTemplate;
        this.batchSize = batchSize;
    }

    @Override
    public int tier() {
        return 4;
    }

    @Override
    public String description() {
        return "JDBC batchUpdate, " + batchSize + " rows/batch";
    }

    @Override
    public long ingest(Iterator<CampaignEvent> events, BenchmarkReporter reporter) {
        long inserted = 0;
        List<CampaignEvent> batch = new ArrayList<>(batchSize);
        while (events.hasNext()) {
            batch.add(events.next());
            if (batch.size() == batchSize || !events.hasNext()) {
                inserted += flushBatch(batch, reporter);
                batch.clear();
            }
        }
        return inserted;
    }

    /** One batchUpdate round-trip. Also the buffered REST pipeline's flush path (it batches like tier 4 under the hood). */
    public long flushBatch(List<CampaignEvent> batch, BenchmarkReporter reporter) {
        long t0 = System.nanoTime();
        try {
            jdbcTemplate.batchUpdate(INSERT_SQL, new BatchPreparedStatementSetter() {
                @Override
                public void setValues(PreparedStatement ps, int i) throws SQLException {
                    CampaignEvent e = batch.get(i);
                    ps.setTimestamp(1, Timestamp.from(e.eventTime()));
                    ps.setString(2, e.eventType());
                    ps.setString(3, e.userId());
                    ps.setString(4, e.sessionId());
                    ps.setString(5, e.campaignId());
                    ps.setString(6, e.channel());
                    ps.setString(7, e.source());
                    ps.setString(8, e.medium());
                    ps.setString(9, e.adGroup());
                    ps.setString(10, e.keyword());
                    ps.setString(11, e.landingPage());
                    ps.setObject(12, e.conversionValue());
                    ps.setString(13, e.currency());
                    ps.setString(14, e.country());
                    ps.setString(15, e.deviceType());
                    ps.setString(16, e.properties());
                }

                @Override
                public int getBatchSize() {
                    return batch.size();
                }
            });
            reporter.recordFlush(batch.size(), System.nanoTime() - t0);
            return batch.size();
        } catch (RuntimeException ex) {
            reporter.recordError(ex);
            return 0;
        }
    }
}
