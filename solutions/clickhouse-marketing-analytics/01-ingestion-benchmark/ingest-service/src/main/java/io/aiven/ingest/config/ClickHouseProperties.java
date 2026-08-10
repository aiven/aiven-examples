package io.aiven.ingest.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Single source of truth for the ClickHouse endpoint. The JDBC DataSource
 * (tiers 0-3) is derived from these values in application.yml; the client-v2
 * bean (tiers 4-5) reads them directly. Switch local Docker <-> Aiven purely
 * via profile/env, never via code.
 */
@ConfigurationProperties(prefix = "clickhouse")
public record ClickHouseProperties(
        String host,
        int port,
        boolean ssl,
        String database,
        String username,
        String password) {

    public String httpUrl() {
        return (ssl ? "https://" : "http://") + host + ":" + port;
    }

    public String jdbcUrl() {
        return "jdbc:ch://" + host + ":" + port + "/" + database + "?ssl=" + ssl;
    }
}
