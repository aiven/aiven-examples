package io.aiven.ingest.api;

import com.fasterxml.jackson.databind.PropertyNamingStrategies;
import com.fasterxml.jackson.databind.annotation.JsonNaming;

/**
 * Body of POST /benchmarks. Only {@code tier} is required; every other field
 * falls back to the ingest.* defaults from application.yml, so a run can be as
 * simple as {"tier": 5}. Fields that don't apply to the chosen tier are
 * ignored (e.g. writers for tier 4).
 */
@JsonNaming(PropertyNamingStrategies.SnakeCaseStrategy.class)
public record BenchmarkRequest(
        Integer tier,
        Long rows,
        Long seed,
        Integer batchSize,       // Tiers 2-5
        Integer concurrency,     // tier 3 (defaults to 80 senders)
        String format,           // Tiers 4-5: RowBinary | JSONEachRow
        Integer writers,         // tier 6
        Integer bufferCapacity,  // tier 0 (buffered REST pipeline)
        Long flushIntervalMs) {  // tier 0 (buffered REST pipeline)
}
