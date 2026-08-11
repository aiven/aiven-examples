package io.aiven.loadgen.run;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonProperty;

import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.atomic.AtomicLong;

/**
 * One load-test run: live counters while running, frozen summary once done.
 * Serialized as the GET /loadtests/{id} response.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public final class LoadTestRun {

    public enum State { RUNNING, COMPLETED, FAILED }

    private final String id;
    private final Map<String, Object> params;
    private final Instant startedAt = Instant.now();
    private volatile Instant finishedAt;
    private volatile State state = State.RUNNING;
    private volatile String error;

    final AtomicLong requestsSent = new AtomicLong();
    final AtomicLong eventsAccepted = new AtomicLong();
    final AtomicLong eventsRejected = new AtomicLong();
    final AtomicLong requestErrors = new AtomicLong();
    // Reservoir of request latencies (µs), sampled; enough for p50/p99.
    final ConcurrentLinkedQueue<Long> latenciesMicros = new ConcurrentLinkedQueue<>();
    final ConcurrentLinkedQueue<Long> probeLatenciesMs = new ConcurrentLinkedQueue<>();

    LoadTestRun(String id, Map<String, Object> params) {
        this.id = id;
        this.params = params;
    }

    void completed() {
        finishedAt = Instant.now();
        state = State.COMPLETED;
    }

    void failed(Exception e) {
        finishedAt = Instant.now();
        state = State.FAILED;
        error = e.toString();
    }

    @JsonProperty
    public String id() {
        return id;
    }

    @JsonProperty
    public State state() {
        return state;
    }

    @JsonProperty
    public String error() {
        return error;
    }

    @JsonProperty
    public Map<String, Object> params() {
        return params;
    }

    @JsonProperty("started_at")
    public Instant startedAt() {
        return startedAt;
    }

    @JsonProperty("finished_at")
    public Instant finishedAt() {
        return finishedAt;
    }

    @JsonProperty("elapsed_s")
    public double elapsedSeconds() {
        Instant end = finishedAt != null ? finishedAt : Instant.now();
        return Duration.between(startedAt, end).toMillis() / 1000.0;
    }

    @JsonProperty("requests_sent")
    public long requestsSent() {
        return requestsSent.get();
    }

    @JsonProperty("events_accepted")
    public long eventsAccepted() {
        return eventsAccepted.get();
    }

    @JsonProperty("events_rejected_429")
    public long eventsRejected() {
        return eventsRejected.get();
    }

    @JsonProperty("request_errors")
    public long requestErrors() {
        return requestErrors.get();
    }

    @JsonProperty("events_per_sec")
    public long eventsPerSec() {
        double s = elapsedSeconds();
        return s > 0 ? Math.round(eventsAccepted.get() / s) : 0;
    }

    @JsonProperty("request_latency_ms")
    public Map<String, Double> requestLatency() {
        return percentiles(latenciesMicros, 1000.0);
    }

    /** Event accepted -> queryable in ClickHouse; only when the probe ran. */
    @JsonProperty("e2e_latency_ms")
    public Map<String, Double> probeLatency() {
        return probeLatenciesMs.isEmpty() ? null : percentiles(probeLatenciesMs, 1.0);
    }

    private static Map<String, Double> percentiles(ConcurrentLinkedQueue<Long> raw, double divisor) {
        List<Long> values = raw.stream().sorted().toList();
        if (values.isEmpty()) {
            return Map.of();
        }
        return Map.of(
                "p50", values.get((int) (values.size() * 0.50)) / divisor,
                "p99", values.get(Math.min((int) (values.size() * 0.99), values.size() - 1)) / divisor,
                "samples", (double) values.size());
    }
}
