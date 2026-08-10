package io.aiven.ingest.tier.tier6;

import io.aiven.ingest.bench.BenchmarkReporter;
import io.aiven.ingest.model.CampaignEvent;
import io.aiven.ingest.tier.IngestTier;
import io.aiven.ingest.tier.tier5.NativeStreamService;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.concurrent.Executors;
import java.util.concurrent.Semaphore;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Tier 6 - N parallel writers (--writers=4..8), each shipping independent
 * tier 5 RowBinary batches. ClickHouse merges parallel large inserts fine (one
 * part per batch, same as tier 5 - just N at a time), so throughput scales
 * with writers until client CPU (serialization) or uplink bandwidth saturates.
 * The semaphore bounds read-ahead so a slow server backpressures the generator
 * instead of ballooning heap. The headline number of the ladder.
 */
@Service
public class ParallelStreamRunner implements IngestTier {

    private final NativeStreamService tier4;
    private final int writers;
    private final int batchSize;

    public ParallelStreamRunner(NativeStreamService tier4,
                                @Value("${ingest.writers:4}") int writers,
                                @Value("${ingest.batch-size:10000}") int batchSize) {
        this.tier4 = tier4;
        this.writers = writers;
        this.batchSize = batchSize;
    }

    @Override
    public int tier() {
        return 6;
    }

    @Override
    public String description() {
        return writers + " parallel RowBinary writers, " + batchSize + " rows/batch";
    }

    @Override
    public long ingest(Iterator<CampaignEvent> events, BenchmarkReporter reporter) throws Exception {
        AtomicLong inserted = new AtomicLong();
        // writers in flight + writers batches staged: enough to keep every
        // writer busy, small enough to backpressure the generator.
        Semaphore inFlight = new Semaphore(writers * 2);
        try (var executor = Executors.newFixedThreadPool(writers)) {
            List<CampaignEvent> batch = new ArrayList<>(batchSize);
            while (events.hasNext()) {
                batch.add(events.next());
                if (batch.size() == batchSize || !events.hasNext()) {
                    List<CampaignEvent> toSend = List.copyOf(batch);
                    batch.clear();
                    inFlight.acquire();
                    executor.submit(() -> {
                        try {
                            inserted.addAndGet(tier4.flushBatch(toSend, reporter));
                        } finally {
                            inFlight.release();
                        }
                    });
                }
            }
        } // close() waits for all submitted batches
        return inserted.get();
    }
}
