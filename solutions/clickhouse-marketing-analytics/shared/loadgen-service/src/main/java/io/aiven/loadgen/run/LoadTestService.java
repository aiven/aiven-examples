package io.aiven.loadgen.run;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.DistributionSummary;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import jakarta.annotation.PreDestroy;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.Statement;
import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Semaphore;
import java.util.concurrent.ThreadLocalRandom;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Executes load tests against the ingest service's POST /events. One run at a
 * time (a second POST gets a 409): overlapping runs would corrupt each
 * other's numbers, same rule as the ingest service's benchmark API.
 *
 * devices mode - N virtual-thread devices, each uploading 1-5 events then
 * idling 2-6s, honoring 429 Retry-After: the mobile-fleet model.
 *
 * firehose mode - a paced dispatcher targets {@code rate} events/s (default
 * as single-event POSTs - the "producers cannot batch" contract), virtual
 * thread per request, bounded in-flight. Achieved rate is in the results;
 * if it lags the target, the TARGET is saturated (429s/errors) or the
 * loadgen container is undersized (no 429s, low CPU headroom on /actuator).
 *
 * If clickhouse.host is set, a probe thread also sends one marker event per
 * second and polls ClickHouse until it is queryable - the e2e latency
 * (event accepted -> queryable) lands in the run's e2e_latency_ms.
 */
@Service
public class LoadTestService {

    private static final Logger log = LoggerFactory.getLogger(LoadTestService.class);
    private static final int MAX_IN_FLIGHT = 8192;
    private static final int LATENCY_SAMPLE_EVERY = 64;

    // HTTP/2 (the TLS default) is the right transport through an ingress:
    // one client multiplexes over few connections. Its cost - the LB rotating
    // h2 connections (GOAWAY) fails whatever is in flight on them - is
    // handled by the bounded transport retry in post(). (Pinning HTTP/1.1
    // instead makes it far worse: thousands of real TCP+TLS connections trip
    // the ingress's handshake rate limits and the client thrashes.)
    // Deliberately ONE client: each additional client is another h2
    // connection independently subject to the ingress's rotation churn -
    // measured at 8 clients, retries rose ~16x for the same rate.
    private final HttpClient http = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(5))
            .build();

    private final String defaultTargetUrl;
    private final String defaultTargetApiKey;
    private final String chHost;
    private final int chPort;
    private final boolean chSsl;
    private final String chDatabase;
    private final String chUser;
    private final String chPassword;

    // Exported via OTLP -> Thanos -> Grafana; the LoadTestRun counters stay
    // the API's per-run source of truth, these meters are the live telemetry.
    private final Counter mAccepted;
    private final Counter mRejected;
    private final Counter mErrors;
    private final Timer mRequest;
    private final DistributionSummary mE2eLatency;

    private final Map<String, LoadTestRun> runsById = new ConcurrentHashMap<>();
    private final List<LoadTestRun> runsInOrder = new CopyOnWriteArrayList<>();
    private final AtomicReference<LoadTestRun> active = new AtomicReference<>();
    private final AtomicInteger sequence = new AtomicInteger();
    private final ExecutorService coordinator = Executors.newThreadPerTaskExecutor(
            Thread.ofPlatform().name("loadtest-", 0).factory());

    public LoadTestService(MeterRegistry registry,
                           @Value("${loadgen.target.url:http://localhost:8080}") String defaultTargetUrl,
                           @Value("${loadgen.target.api-key:}") String defaultTargetApiKey,
                           @Value("${clickhouse.host:}") String chHost,
                           @Value("${clickhouse.port:8123}") int chPort,
                           @Value("${clickhouse.ssl:false}") boolean chSsl,
                           @Value("${clickhouse.database:campaign_analytics}") String chDatabase,
                           @Value("${clickhouse.username:default}") String chUser,
                           @Value("${clickhouse.password:}") String chPassword) {
        this.defaultTargetUrl = defaultTargetUrl;
        this.defaultTargetApiKey = defaultTargetApiKey;
        this.chHost = chHost;
        this.chPort = chPort;
        this.chSsl = chSsl;
        this.chDatabase = chDatabase;
        this.chUser = chUser;
        this.chPassword = chPassword;
        this.mAccepted = Counter.builder("loadgen.events.accepted").register(registry);
        this.mRejected = Counter.builder("loadgen.events.rejected").register(registry);
        this.mErrors = Counter.builder("loadgen.request.errors").register(registry);
        this.mRequest = Timer.builder("loadgen.request")
                .publishPercentiles(0.5, 0.99)
                .publishPercentileHistogram()
                .register(registry);
        this.mE2eLatency = DistributionSummary.builder("loadgen.e2e.latency")
                .baseUnit("ms")
                .description("event accepted -> queryable in ClickHouse")
                .publishPercentiles(0.5, 0.99)
                .publishPercentileHistogram()
                .register(registry);
    }

    /** @throws IllegalArgumentException on bad parameters (400) */
    public LoadTestRun start(LoadTestRequest request) {
        Params p = resolve(request);
        String id = "load-%03d-%s".formatted(sequence.incrementAndGet(), p.mode);
        LoadTestRun run = new LoadTestRun(id, p.asMap());
        if (!active.compareAndSet(null, run)) {
            throw new LoadTestBusyException(active.get());
        }
        runsById.put(id, run);
        runsInOrder.add(run);
        coordinator.submit(() -> execute(run, p));
        return run;
    }

    public LoadTestRun get(String id) {
        return runsById.get(id);
    }

    public List<LoadTestRun> all() {
        return List.copyOf(runsInOrder);
    }

    private void execute(LoadTestRun run, Params p) {
        log.info("[{}] starting: {}", run.id(), run.params());
        Thread probe = null;
        try (ExecutorService workers = Executors.newVirtualThreadPerTaskExecutor()) {
            long deadlineNanos = System.nanoTime() + TimeUnit.SECONDS.toNanos(p.durationS);
            if (!chHost.isBlank()) {
                probe = Thread.ofVirtual().name("e2e-probe").start(() -> probeLoop(run, p, deadlineNanos));
            }
            if ("devices".equals(p.mode)) {
                runDevices(run, p, workers, deadlineNanos);
            } else {
                runFirehose(run, p, workers, deadlineNanos);
            }
            workers.shutdown();
            workers.awaitTermination(30, TimeUnit.SECONDS);
            run.completed();
            log.info("[{}] completed: {} events accepted ({} /s)",
                    run.id(), run.eventsAccepted(), run.eventsPerSec());
        } catch (Exception e) {
            run.failed(e);
            log.error("[{}] failed", run.id(), e);
        } finally {
            if (probe != null) {
                probe.interrupt();
            }
            active.compareAndSet(run, null);
        }
    }

    /** N devices: upload 1-5 events, idle 2-6s, honor Retry-After on 429. */
    private void runDevices(LoadTestRun run, Params p, ExecutorService workers, long deadlineNanos)
            throws InterruptedException {
        var done = new java.util.concurrent.CountDownLatch(p.users);
        for (int u = 1; u <= p.users; u++) {
            int userId = u;
            workers.submit(() -> {
                try {
                    long iteration = 0;
                    while (System.nanoTime() < deadlineNanos && !Thread.currentThread().isInterrupted()) {
                        int batch = 1 + ThreadLocalRandom.current().nextInt(5);
                        int status = post(run, p, EventFactory.batchBody(userId, iteration++, batch), batch);
                        long idleMs = status == 429
                                ? 1000
                                : 2000 + ThreadLocalRandom.current().nextLong(4000);
                        long remainingMs = (deadlineNanos - System.nanoTime()) / 1_000_000;
                        if (remainingMs <= 0) break;
                        Thread.sleep(Math.min(idleMs, remainingMs));
                    }
                } catch (InterruptedException stop) {
                    Thread.currentThread().interrupt();
                } finally {
                    done.countDown();
                }
            });
        }
        done.await();
    }

    /** Paced dispatcher: p.rate events/s in 20ms ticks, virtual thread per request. */
    private void runFirehose(LoadTestRun run, Params p, ExecutorService workers, long deadlineNanos)
            throws InterruptedException {
        Semaphore inFlight = new Semaphore(MAX_IN_FLIGHT);
        double requestsPerTick = (p.rate / (double) p.batchSize) / 50.0;
        double carry = 0;
        AtomicLong userSeq = new AtomicLong();
        while (System.nanoTime() < deadlineNanos) {
            long tickStart = System.nanoTime();
            carry += requestsPerTick;
            int toSend = (int) carry;
            carry -= toSend;
            for (int i = 0; i < toSend; i++) {
                inFlight.acquire();
                workers.submit(() -> {
                    try {
                        long n = userSeq.incrementAndGet();
                        post(run, p, EventFactory.batchBody((int) (n % 100_000), n, p.batchSize), p.batchSize);
                    } finally {
                        inFlight.release();
                    }
                });
            }
            long sleepMs = 20 - (System.nanoTime() - tickStart) / 1_000_000;
            if (sleepMs > 0) {
                Thread.sleep(sleepMs);
            }
        }
        // Wait for stragglers so the counters are final.
        inFlight.acquire(MAX_IN_FLIGHT);
        inFlight.release(MAX_IN_FLIGHT);
    }

    /** POST one body; updates counters; returns the HTTP status (0 = transport error). */
    private int post(LoadTestRun run, Params p, String body, int eventCount) {
        long t0 = System.nanoTime();
        try {
            HttpResponse<Void> response;
            try {
                response = http.send(eventsRequest(p, body), HttpResponse.BodyHandlers.discarding());
            } catch (java.io.IOException connectionChurn) {
                // One retry for transport-level failures only (connection
                // rotated by an LB mid-flight). Never retries 429/5xx - those
                // are the target speaking and must stay visible. The retry
                // itself is counted, not hidden.
                run.transportRetries.incrementAndGet();
                response = http.send(eventsRequest(p, body), HttpResponse.BodyHandlers.discarding());
            }
            long sent = run.requestsSent.incrementAndGet();
            long elapsedNanos = System.nanoTime() - t0;
            mRequest.record(java.time.Duration.ofNanos(elapsedNanos));
            if (sent % LATENCY_SAMPLE_EVERY == 0) {
                run.latenciesMicros.add(elapsedNanos / 1_000);
            }
            if (response.statusCode() == 202) {
                run.eventsAccepted.addAndGet(eventCount);
                mAccepted.increment(eventCount);
            } else if (response.statusCode() == 429) {
                run.eventsRejected.addAndGet(eventCount);
                mRejected.increment(eventCount);
            } else {
                run.requestErrors.incrementAndGet();
                mErrors.increment();
            }
            return response.statusCode();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            return 0;
        } catch (Exception e) {
            run.requestsSent.incrementAndGet();
            run.requestErrors.incrementAndGet();
            mErrors.increment();
            return 0;
        }
    }

    /** One marker event per second; poll ClickHouse until queryable; record ms. */
    private void probeLoop(LoadTestRun run, Params p, long deadlineNanos) {
        // The probe gets its own HTTP client: the load client's connection
        // pool saturates under load, and the probe must keep sampling
        // through exactly those moments.
        HttpClient probeHttp = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(5))
                .build();
        String jdbcUrl = "jdbc:ch://" + chHost + ":" + chPort + "/" + chDatabase + "?ssl=" + chSsl;
        try (Connection conn = DriverManager.getConnection(jdbcUrl, chUser, chPassword)) {
            int n = 0;
            while (System.nanoTime() < deadlineNanos && !Thread.currentThread().isInterrupted()) {
                String marker = "probe-" + run.id() + "-" + (++n);
                String body = "[{\"event_type\":\"probe\",\"user_id\":\"probe\",\"session_id\":\"probe\","
                        + "\"campaign_id\":\"" + marker + "\",\"channel\":\"direct\",\"country\":\"ID\","
                        + "\"device_type\":\"probe\"}]";
                try {
                    long t0 = System.currentTimeMillis();
                    HttpResponse<Void> response = probeHttp.send(
                            eventsRequest(p, body), HttpResponse.BodyHandlers.discarding());
                    if (response.statusCode() == 202) {
                        Long latency = awaitVisible(conn, marker, t0);
                        if (latency != null) {
                            run.probeLatenciesMs.add(latency);
                            mE2eLatency.record(latency);
                        }
                    }
                } catch (InterruptedException stop) {
                    Thread.currentThread().interrupt();
                    return;
                } catch (Exception transientFailure) {
                    // A sample lost to load is itself a signal; keep probing.
                    log.debug("[{}] probe sample failed: {}", run.id(), transientFailure.toString());
                }
                Thread.sleep(1000);
            }
        } catch (InterruptedException stop) {
            Thread.currentThread().interrupt();
        } catch (Exception e) {
            log.warn("[{}] e2e probe disabled: {}", run.id(), e.toString());
        }
    }

    private Long awaitVisible(Connection conn, String marker, long t0) throws Exception {
        long timeoutAt = t0 + 30_000;
        while (System.currentTimeMillis() < timeoutAt) {
            try (Statement stmt = conn.createStatement();
                 ResultSet rs = stmt.executeQuery(
                         "SELECT count() FROM campaign_events WHERE campaign_id = '" + marker + "'")) {
                if (rs.next() && rs.getLong(1) >= 1) {
                    return System.currentTimeMillis() - t0;
                }
            }
            Thread.sleep(50);
        }
        return null; // timed out; don't poison the percentiles
    }

    private HttpRequest eventsRequest(Params p, String body) {
        HttpRequest.Builder builder = HttpRequest.newBuilder()
                .uri(URI.create(p.targetUrl + "/events"))
                .timeout(Duration.ofSeconds(30))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(body));
        if (!p.targetApiKey.isBlank()) {
            builder.header("X-API-Key", p.targetApiKey);
        }
        return builder.build();
    }

    private Params resolve(LoadTestRequest r) {
        if (r == null || r.mode() == null) {
            throw new IllegalArgumentException("'mode' is required: devices | firehose");
        }
        Params p = new Params();
        p.mode = r.mode();
        if (!"devices".equals(p.mode) && !"firehose".equals(p.mode)) {
            throw new IllegalArgumentException("mode must be devices or firehose, got: " + p.mode);
        }
        p.rate = inRange("rate", r.rate() != null ? r.rate() : 10_000, 1, 1_000_000);
        p.batchSize = inRange("batch_size", r.batchSize() != null ? r.batchSize() : 1, 1, 10_000);
        p.users = inRange("users", r.users() != null ? r.users() : 1_000, 1, 50_000);
        p.durationS = inRange("duration_s", r.durationS() != null ? r.durationS() : 60, 1, 3_600);
        p.targetUrl = (r.targetUrl() != null ? r.targetUrl() : defaultTargetUrl).replaceAll("/+$", "");
        p.targetApiKey = r.targetApiKey() != null ? r.targetApiKey() : defaultTargetApiKey;
        return p;
    }

    private static int inRange(String name, int value, int min, int max) {
        if (value < min || value > max) {
            throw new IllegalArgumentException(
                    "'" + name + "' must be in [" + min + ", " + max + "], got " + value);
        }
        return value;
    }

    @PreDestroy
    void shutdown() {
        coordinator.shutdownNow();
    }

    private static final class Params {
        String mode;
        int rate;
        int batchSize;
        int users;
        int durationS;
        String targetUrl;
        String targetApiKey;

        Map<String, Object> asMap() {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("mode", mode);
            if ("firehose".equals(mode)) {
                m.put("rate", rate);
                m.put("batch_size", batchSize);
            } else {
                m.put("users", users);
            }
            m.put("duration_s", durationS);
            m.put("target_url", targetUrl);
            return m;
        }
    }

    /** 409: a load test is already executing. */
    public static final class LoadTestBusyException extends RuntimeException {
        private final transient LoadTestRun activeRun;

        LoadTestBusyException(LoadTestRun activeRun) {
            super("load test " + (activeRun != null ? activeRun.id() : "?") + " is already running");
            this.activeRun = activeRun;
        }

        public LoadTestRun activeRun() {
            return activeRun;
        }
    }
}
