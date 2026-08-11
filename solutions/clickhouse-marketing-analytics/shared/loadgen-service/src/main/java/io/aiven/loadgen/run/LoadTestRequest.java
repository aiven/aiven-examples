package io.aiven.loadgen.run;

import com.fasterxml.jackson.databind.PropertyNamingStrategies;
import com.fasterxml.jackson.databind.annotation.JsonNaming;

/**
 * Body of POST /loadtests. target_url/target_api_key fall back to the
 * loadgen.target.* defaults from the environment, so on a paired Aiven Apps
 * deploy a run can be as simple as {"mode":"firehose","rate":50000}.
 *
 * Modes:
 *  - devices:  {@code users} virtual devices, each uploading 1-5 events then
 *              idling 2-6s (the mobile-fleet model; ~users/4 events per sec).
 *              Honors 429 Retry-After backoff.
 *  - firehose: {@code rate} events/s total, sent as single-event POSTs (the
 *              "producers cannot batch" contract), for saturation runs.
 *              batch_size > 1 models pre-batched upstream services instead.
 */
@JsonNaming(PropertyNamingStrategies.SnakeCaseStrategy.class)
public record LoadTestRequest(
        String mode,
        Integer rate,          // firehose: target events/s
        Integer batchSize,     // firehose: events per POST (default 1)
        Integer users,         // devices: concurrent virtual devices
        Integer durationS,
        String targetUrl,
        String targetApiKey) {
}
