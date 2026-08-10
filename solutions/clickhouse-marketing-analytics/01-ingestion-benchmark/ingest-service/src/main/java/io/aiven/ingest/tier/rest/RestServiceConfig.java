package io.aiven.ingest.tier.rest;

import io.aiven.ingest.bench.BenchmarkReporterFactory;
import io.aiven.ingest.tier.tier4.JdbcBatchService;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Lazy;

/**
 * The long-lived EventBuffer behind POST /events (service mode). Lazy: created
 * on the first request, so pure benchmark runs (--tier=N) never start a
 * flusher thread they don't use. Benchmark mode builds its own short-lived
 * buffer per run instead (see BufferedIngestService).
 */
@Configuration
public class RestServiceConfig {

    @Bean(destroyMethod = "close")
    @Lazy
    public EventBuffer serviceEventBuffer(JdbcBatchService batchWriter,
                                          BenchmarkReporterFactory reporterFactory,
                                          @Value("${ingest.buffer-capacity:100000}") int capacity,
                                          @Value("${ingest.batch-size:10000}") int batchSize,
                                          @Value("${ingest.flush-interval-ms:1000}") long flushIntervalMs) {
        var reporter = reporterFactory.forRun("rest-service");
        reporter.start();
        return new EventBuffer(batchWriter, reporter, capacity, batchSize, flushIntervalMs, "rest-flusher");
    }
}
