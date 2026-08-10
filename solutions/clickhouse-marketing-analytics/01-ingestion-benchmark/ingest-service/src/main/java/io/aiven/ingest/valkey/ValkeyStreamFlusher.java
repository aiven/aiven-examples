package io.aiven.ingest.valkey;

import com.fasterxml.jackson.databind.ObjectMapper;
import io.aiven.ingest.bench.BenchmarkReporter;
import io.aiven.ingest.bench.BenchmarkReporterFactory;
import io.aiven.ingest.model.CampaignEvent;
import io.aiven.ingest.tier.rest.EventDto;
import io.aiven.ingest.tier.tier5.NativeStreamService;
import com.clickhouse.client.api.insert.InsertSettings;
import io.lettuce.core.Consumer;
import io.lettuce.core.RedisBusyException;
import io.lettuce.core.RedisClient;
import io.lettuce.core.StreamMessage;
import io.lettuce.core.XAutoClaimArgs;
import io.lettuce.core.XGroupCreateArgs;
import io.lettuce.core.XReadArgs;
import io.lettuce.core.XTrimArgs;
import io.lettuce.core.api.StatefulRedisConnection;
import io.lettuce.core.api.sync.RedisCommands;
import io.lettuce.core.models.stream.ClaimedMessages;
import io.lettuce.core.models.stream.PendingMessages;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.SmartLifecycle;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;

/**
 * The consumer half of the Valkey buffer: an in-app flusher that turns the
 * per-event trickle back into the big batches ClickHouse wants, using the
 * ladder's winning insert path (client-v2 RowBinary + LZ4) with async_insert=0
 * pinned per insert - the production recommendation for batch paths.
 *
 * One cycle:
 *   1. reread ingest:config (runtime-tunable batch geometry, one HGETALL)
 *   2. XREADGROUP COUNT batch_size BLOCK flush_interval_ms - wakes with up to
 *      batch_size events, or whatever arrived within the flush interval
 *   3. bulk insert via NativeStreamService.flushBatch
 *   4. XACK the whole batch, then XTRIM MINID up to the oldest un-acked entry:
 *      exactly what is confirmed in ClickHouse gets deleted, nothing else
 *
 * Crash recovery: every instance joins the same consumer group under a unique
 * consumer name; unacked entries of a dead instance sit in the group's pending
 * entries list until a surviving instance reclaims them with XAUTOCLAIM (idle
 * longer than valkey.claim-min-idle-ms, checked on idle cycles). Delivery is
 * therefore at-least-once - a reclaimed batch can be inserted twice; analytics
 * tolerates that, and ClickHouse orders by event_time regardless.
 *
 * Failed inserts are NOT acked: the entries stay pending and are retried by
 * the reclaim path, so a ClickHouse outage stalls the stream (bounded by the
 * sink's max-stream-length backpressure) instead of losing events.
 */
@Component
@ConditionalOnProperty(name = "ingest.buffer", havingValue = "valkey")
public class ValkeyStreamFlusher implements SmartLifecycle {

    private static final Logger log = LoggerFactory.getLogger(ValkeyStreamFlusher.class);
    private static final long ERROR_BACKOFF_MS = 1_000;

    private final RedisClient client;
    private final IngestConfigStore configStore;
    private final NativeStreamService writer;
    private final ObjectMapper mapper;
    private final BenchmarkReporterFactory reporterFactory;
    private final ValkeyProperties props;
    // Batch path: pin async_insert off so the ClickHouse 26.3 server-wide
    // default can never buffer these inserts (README finding 8). best_effort
    // only matters if the writer runs in JSONEachRow mode; harmless otherwise.
    private final InsertSettings insertSettings = new InsertSettings()
            .serverSetting("async_insert", "0")
            .serverSetting("date_time_input_format", "best_effort");

    private volatile boolean running;
    private volatile String lastAckedId;
    private Thread worker;

    public ValkeyStreamFlusher(RedisClient client,
                               IngestConfigStore configStore,
                               NativeStreamService writer,
                               ObjectMapper mapper,
                               BenchmarkReporterFactory reporterFactory,
                               ValkeyProperties props) {
        this.client = client;
        this.configStore = configStore;
        this.writer = writer;
        this.mapper = mapper;
        this.reporterFactory = reporterFactory;
        this.props = props;
    }

    @Override
    public void start() {
        running = true;
        worker = Thread.ofPlatform().name("valkey-flusher").daemon().start(this::run);
    }

    @Override
    public void stop() {
        running = false;
        if (worker != null) {
            try {
                worker.join(10_000);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
        }
    }

    @Override
    public boolean isRunning() {
        return running;
    }

    private void run() {
        BenchmarkReporter reporter = reporterFactory.forRun("valkey-flusher");
        reporter.start();
        // XREADGROUP BLOCK parks its connection, so the flusher gets its own
        // instead of sharing the producer/config one.
        try (StatefulRedisConnection<String, String> connection = client.connect()) {
            RedisCommands<String, String> commands = connection.sync();
            ensureGroup(commands);
            log.info("Valkey flusher started: stream={} group={} consumer={}",
                    props.stream(), props.group(), props.consumer());
            while (running) {
                try {
                    cycle(commands, reporter);
                } catch (Exception e) {
                    if (!running) return;
                    log.warn("Flusher cycle failed ({}); retrying in {} ms",
                            e.getMessage(), ERROR_BACKOFF_MS);
                    sleep(ERROR_BACKOFF_MS);
                }
            }
        } catch (Exception e) {
            log.error("Valkey flusher terminated: cannot connect to {}", props.stream(), e);
        }
    }

    private void cycle(RedisCommands<String, String> commands, BenchmarkReporter reporter) {
        IngestTuning tuning = configStore.current();
        List<StreamMessage<String, String>> messages = commands.xreadgroup(
                Consumer.from(props.group(), props.consumer()),
                XReadArgs.Builder.count(tuning.batchSize()).block(tuning.flushIntervalMs()),
                XReadArgs.StreamOffset.lastConsumed(props.stream()));
        if (messages == null || messages.isEmpty()) {
            // Idle: a good moment to pick up entries a dead instance left pending.
            messages = reclaimStale(commands, tuning.batchSize());
            if (messages.isEmpty()) {
                return;
            }
        }
        flush(commands, messages, reporter);
    }

    private void flush(RedisCommands<String, String> commands,
                       List<StreamMessage<String, String>> messages,
                       BenchmarkReporter reporter) {
        List<CampaignEvent> batch = new ArrayList<>(messages.size());
        List<String> parsedIds = new ArrayList<>(messages.size());
        String[] poisonIds = messages.stream()
                .filter(m -> !parseInto(m, batch, parsedIds))
                .map(StreamMessage::getId)
                .toArray(String[]::new);
        if (poisonIds.length > 0) {
            // Unparseable entries would redeliver forever; ack + drop, loudly.
            log.error("Dropping {} malformed stream entries (first id: {})",
                    poisonIds.length, poisonIds[0]);
            commands.xack(props.stream(), props.group(), poisonIds);
        }
        if (batch.isEmpty()) {
            return;
        }
        long inserted = writer.flushBatch(batch, reporter, insertSettings);
        if (inserted == batch.size()) {
            commands.xack(props.stream(), props.group(), parsedIds.toArray(String[]::new));
            lastAckedId = parsedIds.getLast(); // entries arrive in id order
            trimAcknowledged(commands);
        } else {
            // Not acked: the entries stay pending and come back via the
            // reclaim path once they pass claim-min-idle-ms.
            log.warn("Batch insert failed ({} rows); leaving entries pending for retry",
                    batch.size());
            sleep(ERROR_BACKOFF_MS);
        }
    }

    private boolean parseInto(StreamMessage<String, String> message,
                              List<CampaignEvent> batch, List<String> ids) {
        String json = message.getBody().get(ValkeyEventSink.FIELD_JSON);
        if (json == null) {
            return false;
        }
        try {
            batch.add(mapper.readValue(json, EventDto.class).toCampaignEvent());
            ids.add(message.getId());
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    /** Delete everything below the oldest un-acked entry - i.e. exactly what is confirmed inserted. */
    private void trimAcknowledged(RedisCommands<String, String> commands) {
        PendingMessages pending = commands.xpending(props.stream(), props.group());
        // With entries still pending (another instance mid-flush, or a failed
        // batch awaiting reclaim) trim only below the oldest of them; with a
        // clean PEL, everything up to our last ack is confirmed in ClickHouse.
        String minId = pending.getCount() > 0
                ? pending.getMessageIds().getLower().getValue()
                : lastAckedId;
        if (minId != null) {
            commands.xtrim(props.stream(), XTrimArgs.Builder.minId(minId));
        }
    }

    /** XAUTOCLAIM: adopt entries a crashed/stuck consumer left pending too long. */
    private List<StreamMessage<String, String>> reclaimStale(
            RedisCommands<String, String> commands, int count) {
        ClaimedMessages<String, String> claimed = commands.xautoclaim(
                props.stream(),
                XAutoClaimArgs.Builder.xautoclaim(
                                Consumer.from(props.group(), props.consumer()),
                                props.claimMinIdleMs(), "0-0")
                        .count(count));
        List<StreamMessage<String, String>> messages = claimed.getMessages();
        if (!messages.isEmpty()) {
            log.info("Reclaimed {} stale pending entries from the group", messages.size());
        }
        return messages;
    }

    private void ensureGroup(RedisCommands<String, String> commands) {
        try {
            // From "0": a group created against a pre-existing stream consumes
            // the backlog too, not just new entries.
            commands.xgroupCreate(
                    XReadArgs.StreamOffset.from(props.stream(), "0"),
                    props.group(),
                    XGroupCreateArgs.Builder.mkstream());
        } catch (RedisBusyException alreadyExists) {
            // BUSYGROUP: another instance created it first. Exactly what we want.
        }
    }

    private static void sleep(long ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
