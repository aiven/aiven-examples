package io.aiven.ingest.config;

import com.clickhouse.client.api.Client;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Lazy;

/**
 * Official com.clickhouse client-v2 for tiers 4-5 (RowBinary streaming + LZ4).
 * Lazy: only built when a tier that needs it runs, so JDBC-only tiers don't
 * open a second connection pool.
 */
@Configuration
public class ClickHouseClientConfig {

    @Bean(destroyMethod = "close")
    @Lazy
    public Client clickHouseClient(ClickHouseProperties props) {
        return new Client.Builder()
                .addEndpoint(props.httpUrl())
                .setUsername(props.username())
                .setPassword(props.password())
                .setDefaultDatabase(props.database())
                // LZ4 request compression matters a lot over TLS/WAN to Aiven.
                .compressClientRequest(true)
                .build();
    }
}
