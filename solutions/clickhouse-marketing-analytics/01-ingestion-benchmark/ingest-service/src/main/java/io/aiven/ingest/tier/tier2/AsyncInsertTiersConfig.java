package io.aiven.ingest.tier.tier2;

import io.aiven.ingest.tier.IngestTier;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.JdbcTemplate;

/**
 * AsyncInsertService covers two ladder rungs; register one bean per rung so
 * --tier=2 and --tier=3 both resolve.
 */
@Configuration
public class AsyncInsertTiersConfig {

    @Bean
    public IngestTier tier2AsyncSequential(
            @Qualifier("asyncInsert") JdbcTemplate asyncInsertJdbcTemplate) {
        return new AsyncInsertService(asyncInsertJdbcTemplate, 1);
    }

    /** Tier 3: --concurrency=N overrides; plain --tier=3 gets the benchmark's 80 senders. */
    @Bean
    public IngestTier tier3AsyncConcurrent(
            @Qualifier("asyncInsert") JdbcTemplate asyncInsertJdbcTemplate,
            @Value("${ingest.concurrency:1}") int concurrency) {
        return new AsyncInsertService(asyncInsertJdbcTemplate,
                concurrency > 1 ? concurrency : AsyncInsertService.AIVEN_SAFE_MAX_CONCURRENCY);
    }
}
