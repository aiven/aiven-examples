package io.aiven.ingest.config;

import com.zaxxer.hikari.HikariDataSource;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;
import org.springframework.jdbc.core.JdbcTemplate;

/**
 * Two explicit connection pools against the same ClickHouse (defined by
 * clickhouse.* properties, so local Docker <-> Aiven stays a profile switch):
 *
 * - "clickhouse-main": plain connection, used by Tiers 0/2/3.
 * - "clickhouse-async-insert": identical except the JDBC URL carries the
 *   async_insert server settings - tier 2's entire fix, expressed as config.
 *   jdbc-v2 passes any "clickhouse_setting_*" URL parameter through as a
 *   ClickHouse setting (the modern equivalent of the customer's custom_http_params).
 *   The INSERT SQL stays byte-for-byte identical to tier 1.
 *
 * The settings can't ride on the statement itself: a SETTINGS clause between
 * the column list and VALUES breaks the jdbc-v2 (0.9.0) prepared-statement
 * parameter parser.
 *
 * wait_for_async_insert=0 = fire-and-forget (a deliberate delivery-guarantee
 * tradeoff); async_insert_deduplicate=0 so identical benchmark payloads aren't
 * silently dropped. Pool max 100 = Aiven's concurrent-query plan limit; tier 3
 * needs one pooled connection per in-flight virtual-thread sender (a blocked
 * virtual thread waiting for a connection gains nothing). Connections open
 * lazily.
 */
@Configuration
public class ClickHouseJdbcConfig {

    /**
     * LZ4-compress request bodies ("decompress" is client-v2's historic key
     * for it: the client compresses, the server decompresses). Measured
     * effect from a laptop to Aiven: a 10k-row batch is ~3MB of VALUES text,
     * and uncompressed uploads were WAN-bandwidth-bound at ~5s per batch.
     */
    static final String CLIENT_OPTIONS = "decompress=true";

    /**
     * The baseline pins async_insert OFF server-side, so tier 1
     * behaves like the customer's original environment even on ClickHouse >= 26.3 where
     * async_insert defaults to on. (Empirically the server already disables
     * async for JDBC inline-VALUES inserts, but the demo claim should not
     * hinge on that implementation detail.) For tier 4 batches, synchronous
     * inserts are what you want anyway: one batch = one part, acknowledged.
     */
    static final String BASELINE_SETTINGS = "clickhouse_setting_async_insert=0";

    static final String ASYNC_SETTINGS =
            "clickhouse_setting_async_insert=1"
                    + "&clickhouse_setting_wait_for_async_insert=0"
                    + "&clickhouse_setting_async_insert_busy_timeout_ms=1000"
                    + "&clickhouse_setting_async_insert_max_data_size=10485760"
                    + "&clickhouse_setting_async_insert_deduplicate=0";

    @Bean(destroyMethod = "close")
    @Primary
    public HikariDataSource dataSource(ClickHouseProperties props) {
        return pool(props, props.jdbcUrl() + "&" + CLIENT_OPTIONS + "&" + BASELINE_SETTINGS,
                "clickhouse-main");
    }

    @Bean
    @Primary
    public JdbcTemplate jdbcTemplate(HikariDataSource dataSource) {
        return new JdbcTemplate(dataSource);
    }

    @Bean(destroyMethod = "close")
    @Qualifier("asyncInsert")
    public HikariDataSource asyncInsertDataSource(ClickHouseProperties props) {
        return pool(props, props.jdbcUrl() + "&" + CLIENT_OPTIONS + "&" + ASYNC_SETTINGS,
                "clickhouse-async-insert");
    }

    @Bean
    @Qualifier("asyncInsert")
    public JdbcTemplate asyncInsertJdbcTemplate(
            @Qualifier("asyncInsert") HikariDataSource asyncInsertDataSource) {
        return new JdbcTemplate(asyncInsertDataSource);
    }

    private HikariDataSource pool(ClickHouseProperties props, String url, String name) {
        HikariDataSource ds = new HikariDataSource();
        ds.setJdbcUrl(url);
        ds.setUsername(props.username());
        ds.setPassword(props.password());
        ds.setDriverClassName("com.clickhouse.jdbc.ClickHouseDriver");
        ds.setMaximumPoolSize(100);
        ds.setMinimumIdle(1);
        ds.setPoolName(name);
        return ds;
    }
}
