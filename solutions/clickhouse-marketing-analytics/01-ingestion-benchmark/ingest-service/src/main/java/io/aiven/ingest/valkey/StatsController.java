package io.aiven.ingest.valkey;

import io.aiven.ingest.bench.BenchmarkReporter;
import io.lettuce.core.api.StatefulRedisConnection;
import io.lettuce.core.api.sync.RedisCommands;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Live counters for the Valkey ingestion path - the observation point for the
 * mini-benchmark (sample it on a timer while the load generator runs):
 *
 *   GET /stats -> rows flushed / batches / errors / rows_per_sec since start,
 *                 the tuning currently in force, and the stream's health
 *                 (XLEN = backlog, XPENDING = delivered-not-yet-acked).
 *
 * A growing stream_length means the flushers are behind the producers; a
 * non-zero pending count during steady state means a consumer died mid-flush
 * and its entries await XAUTOCLAIM.
 */
@RestController
@ConditionalOnProperty(name = "ingest.buffer", havingValue = "valkey")
public class StatsController {

    private final ValkeyStreamFlusher flusher;
    private final IngestConfigStore configStore;
    private final RedisCommands<String, String> commands;
    private final ValkeyProperties props;

    public StatsController(ValkeyStreamFlusher flusher,
                           IngestConfigStore configStore,
                           StatefulRedisConnection<String, String> connection,
                           ValkeyProperties props) {
        this.flusher = flusher;
        this.configStore = configStore;
        this.commands = connection.sync();
        this.props = props;
    }

    @GetMapping("/stats")
    public Map<String, Object> stats() {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("mode", "valkey");
        body.put("consumer", flusher.consumerName());

        BenchmarkReporter reporter = flusher.reporter();
        Map<String, Object> f = new LinkedHashMap<>();
        if (reporter != null) {
            BenchmarkReporter.Summary s = reporter.summary();
            f.put("rows_flushed", s.rows());
            f.put("batches", s.flushes());
            f.put("errors", s.errors());
            f.put("rows_per_sec_since_start", Math.round(s.rowsPerSec()));
            f.put("flush_p50_ms", s.flushP50Ms());
            f.put("flush_p99_ms", s.flushP99Ms());
            f.put("uptime_seconds", Math.round(s.wallSeconds()));
        }
        body.put("flusher", f);

        IngestTuning tuning = configStore.current();
        body.put("tuning", Map.of(
                "batch_size", tuning.batchSize(),
                "flush_interval_ms", tuning.flushIntervalMs()));

        Map<String, Object> stream = new LinkedHashMap<>();
        stream.put("name", props.stream());
        stream.put("length", commands.xlen(props.stream()));
        try {
            stream.put("pending", commands.xpending(props.stream(), props.group()).getCount());
        } catch (Exception groupNotCreatedYet) {
            // NOGROUP: the flusher hasn't run ensureGroup yet (startup race).
            stream.put("pending", 0);
        }
        body.put("stream", stream);
        return body;
    }
}
