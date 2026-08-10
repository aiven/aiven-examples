package io.aiven.ingest;

import org.junit.jupiter.api.Test;

import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.Statement;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Schema acceptance: the exact DDL files create cleanly (done once in the
 * shared base class - a failure there fails every test) and the schema matches
 * the plan: 16 columns, the customer campaign_id deviation, MergeTree with the blog's
 * partition/sort key, and a working rollup MV.
 */
class SchemaIntegrationTest extends AbstractClickHouseIntegrationTest {

    @Test
    void campaignEventsSchemaMatchesPlan() throws Exception {
        try (Connection conn = connect(); Statement stmt = conn.createStatement()) {
            ResultSet rs = stmt.executeQuery("""
                    SELECT count() FROM system.columns
                    WHERE database = 'campaign_analytics' AND table = 'campaign_events'""");
            rs.next();
            assertThat(rs.getLong(1)).as("column count").isEqualTo(16);

            rs = stmt.executeQuery("""
                    SELECT type, default_expression FROM system.columns
                    WHERE database = 'campaign_analytics' AND table = 'campaign_events'
                      AND name = 'campaign_id'""");
            rs.next();
            // The customer's deviation from the blog: non-Nullable LowCardinality with '' default.
            assertThat(rs.getString(1)).isEqualTo("LowCardinality(String)");
            assertThat(rs.getString(2)).isEqualTo("''");

            rs = stmt.executeQuery("""
                    SELECT engine, partition_key, sorting_key FROM system.tables
                    WHERE database = 'campaign_analytics' AND name = 'campaign_events'""");
            rs.next();
            assertThat(rs.getString(1)).contains("MergeTree");
            assertThat(rs.getString(2)).isEqualTo("toYYYYMM(event_time)");
            assertThat(rs.getString(3)).isEqualTo("channel, campaign_id, event_time, user_id");
        }
    }

    @Test
    void rollupMaterializedViewPopulatesOnInsert() throws Exception {
        try (Connection conn = connect(); Statement stmt = conn.createStatement()) {
            stmt.execute("""
                    INSERT INTO campaign_events
                    (event_time, event_type, user_id, session_id, campaign_id, channel,
                     source, medium, ad_group, keyword, landing_page, conversion_value,
                     currency, country, device_type, properties)
                    VALUES
                    (now64(3), 'purchase', 'u-mv-test', 's-mv-test', 'cmp-mv', 'email',
                     'newsletter', 'email', NULL, NULL, '/lp/1', 150000.0,
                     'IDR', 'ID', 'mobile', '{}')""");

            ResultSet rs = stmt.executeQuery("""
                    SELECT uniqMerge(users), sum(purchases), sumMerge(revenue)
                    FROM daily_campaign_rollup
                    WHERE campaign_id = 'cmp-mv'""");
            rs.next();
            assertThat(rs.getLong(1)).as("uniq users in rollup").isEqualTo(1);
            assertThat(rs.getLong(2)).as("purchases in rollup").isEqualTo(1);
            assertThat(rs.getDouble(3)).as("revenue in rollup").isEqualTo(150000.0);
        }
    }
}
