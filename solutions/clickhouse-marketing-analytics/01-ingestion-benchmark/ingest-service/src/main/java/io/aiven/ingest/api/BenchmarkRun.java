package io.aiven.ingest.api;

import io.aiven.ingest.bench.BenchmarkReporter;

import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * One benchmark run's lifecycle, safe to snapshot from any request thread
 * while the run executes on the runner thread. The reporter is live: status
 * responses expose rows/throughput mid-run, so a WAN run's progress is
 * visible long before it finishes.
 */
public final class BenchmarkRun {

    public enum State { RUNNING, COMPLETED, FAILED }

    private final String id;
    private final int tier;
    private final String description;
    private final Map<String, Object> params;
    private final long requestedRows;
    private final BenchmarkReporter reporter;
    private final Instant startedAt = Instant.now();

    private volatile State state = State.RUNNING;
    private volatile Instant finishedAt;
    private volatile String error;

    BenchmarkRun(String id, int tier, String description, Map<String, Object> params,
                 long requestedRows, BenchmarkReporter reporter) {
        this.id = id;
        this.tier = tier;
        this.description = description;
        this.params = params;
        this.requestedRows = requestedRows;
        this.reporter = reporter;
    }

    String id() {
        return id;
    }

    BenchmarkReporter reporter() {
        return reporter;
    }

    void completed() {
        state = State.COMPLETED;
        finishedAt = Instant.now();
    }

    void failed(Throwable t) {
        state = State.FAILED;
        finishedAt = Instant.now();
        error = t.toString();
    }

    /** JSON shape of GET /benchmarks/{id} (snake_case, like the /events API). */
    Map<String, Object> toStatus() {
        BenchmarkReporter.Summary s = reporter.summary();
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("id", id);
        body.put("tier", tier);
        body.put("description", description);
        body.put("state", state.name());
        body.put("params", params);
        body.put("requested_rows", requestedRows);
        body.put("rows_inserted", s.rows());
        body.put("progress_pct", requestedRows == 0 ? 100.0
                : Math.round(s.rows() * 1000.0 / requestedRows) / 10.0);
        body.put("wall_seconds", Math.round(s.wallSeconds() * 100.0) / 100.0);
        body.put("rows_per_sec", Math.round(s.rowsPerSec()));
        body.put("flushes", s.flushes());
        body.put("flush_p50_ms", Math.round(s.flushP50Ms() * 100.0) / 100.0);
        body.put("flush_p99_ms", Math.round(s.flushP99Ms() * 100.0) / 100.0);
        body.put("errors", s.errors());
        body.put("started_at", startedAt.toString());
        body.put("finished_at", finishedAt != null ? finishedAt.toString() : null);
        body.put("error", error);
        return body;
    }
}
