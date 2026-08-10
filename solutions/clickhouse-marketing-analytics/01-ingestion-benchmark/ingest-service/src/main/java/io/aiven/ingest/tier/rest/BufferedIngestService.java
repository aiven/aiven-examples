package io.aiven.ingest.tier.rest;

import io.aiven.ingest.bench.BenchmarkReporter;
import io.aiven.ingest.model.CampaignEvent;
import io.aiven.ingest.tier.IngestTier;
import io.aiven.ingest.tier.tier4.JdbcBatchService;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.util.Iterator;

/**
 * The buffered REST ingestion pipeline (--tier=0, off the ladder): REST
 * /events endpoint (EventController) -> bounded EventBuffer -> flush on
 * >= batch-size rows OR flush-interval-ms -> tier 4 batch insert. Backpressure
 * via 429 on queue overflow.
 *
 * Benchmark mode (--tier=3) pushes the generator through the same buffer with
 * blocking puts, so the number measures the buffer+flush pipeline itself; the
 * HTTP layer on top is exercised by the k6 scenario in loadtest/.
 */
@Service
public class BufferedIngestService implements IngestTier {

    private final JdbcBatchService batchWriter;
    private final int capacity;
    private final int batchSize;
    private final long flushIntervalMs;

    public BufferedIngestService(JdbcBatchService batchWriter,
                                 @Value("${ingest.buffer-capacity:100000}") int capacity,
                                 @Value("${ingest.batch-size:10000}") int batchSize,
                                 @Value("${ingest.flush-interval-ms:1000}") long flushIntervalMs) {
        this.batchWriter = batchWriter;
        this.capacity = capacity;
        this.batchSize = batchSize;
        this.flushIntervalMs = flushIntervalMs;
    }

    @Override
    public int tier() {
        return 0;
    }

    @Override
    public String description() {
        return "buffered ingest (queue " + capacity + ", flush " + batchSize
                + " rows or " + flushIntervalMs + " ms)";
    }

    @Override
    public long ingest(Iterator<CampaignEvent> events, BenchmarkReporter reporter) throws Exception {
        EventBuffer buffer = new EventBuffer(batchWriter, reporter,
                capacity, batchSize, flushIntervalMs, "rest-bench-flusher");
        try (buffer) {
            while (events.hasNext()) {
                buffer.put(events.next());
            }
        } // close() drains the queue and waits for the last flush
        return buffer.rowsFlushed();
    }
}
