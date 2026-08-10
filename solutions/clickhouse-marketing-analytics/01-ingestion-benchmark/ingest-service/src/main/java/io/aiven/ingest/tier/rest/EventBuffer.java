package io.aiven.ingest.tier.rest;

import io.aiven.ingest.bench.BenchmarkReporter;
import io.aiven.ingest.model.CampaignEvent;
import io.aiven.ingest.tier.tier4.JdbcBatchService;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;

/**
 * The heart of the buffered REST pipeline: a bounded in-memory queue drained by one flusher thread
 * that batch-inserts on >= batchSize rows OR flushIntervalMs since the first
 * buffered event, whichever comes first - so event->queryable latency stays
 * bounded at roughly the flush interval even at trickle rates.
 *
 * Backpressure: offer() returns false when the queue is full (the REST layer
 * turns that into a 429); put() blocks (a well-behaved client honoring
 * backpressure - the benchmark path). In-flight rows are lost on crash: that
 * is the honest durability gap a Kafka log would close later.
 */
public final class EventBuffer implements AutoCloseable {

    private final ArrayBlockingQueue<CampaignEvent> queue;
    private final JdbcBatchService batchWriter;
    private final BenchmarkReporter reporter;
    private final int batchSize;
    private final long flushIntervalNanos;
    private final Thread flusher;
    private final AtomicLong rowsFlushed = new AtomicLong();
    private volatile boolean running = true;

    public EventBuffer(JdbcBatchService batchWriter, BenchmarkReporter reporter,
                       int capacity, int batchSize, long flushIntervalMs, String flusherName) {
        this.batchWriter = batchWriter;
        this.reporter = reporter;
        this.queue = new ArrayBlockingQueue<>(capacity);
        this.batchSize = batchSize;
        this.flushIntervalNanos = TimeUnit.MILLISECONDS.toNanos(flushIntervalMs);
        this.flusher = Thread.ofPlatform().name(flusherName).daemon().start(this::flushLoop);
    }

    /** Non-blocking enqueue; false = queue full = caller should back off (429). */
    public boolean offer(CampaignEvent event) {
        return running && queue.offer(event);
    }

    /** Blocking enqueue: a client that honors backpressure instead of dropping. */
    public void put(CampaignEvent event) throws InterruptedException {
        queue.put(event);
    }

    public int queueDepth() {
        return queue.size();
    }

    public long rowsFlushed() {
        return rowsFlushed.get();
    }

    private void flushLoop() {
        List<CampaignEvent> batch = new ArrayList<>(batchSize);
        long deadline = System.nanoTime() + flushIntervalNanos;
        while (true) {
            if (batch.isEmpty()) {
                // Interval is measured from the first buffered event, not wall time.
                deadline = System.nanoTime() + flushIntervalNanos;
            }
            CampaignEvent head = null;
            try {
                head = queue.poll(50, TimeUnit.MILLISECONDS);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                return;
            }
            if (head != null) {
                batch.add(head);
                queue.drainTo(batch, batchSize - batch.size());
            }
            boolean stopped = !running;
            if (stopped) {
                queue.drainTo(batch);
            }
            if (!batch.isEmpty() && (batch.size() >= batchSize || System.nanoTime() >= deadline || stopped)) {
                flush(batch);
                batch.clear();
            }
            if (stopped && queue.isEmpty() && batch.isEmpty()) {
                return;
            }
        }
    }

    private void flush(List<CampaignEvent> batch) {
        // The final drain on close() may exceed batchSize; keep parts bounded.
        for (int from = 0; from < batch.size(); from += batchSize) {
            List<CampaignEvent> chunk = batch.subList(from, Math.min(from + batchSize, batch.size()));
            rowsFlushed.addAndGet(batchWriter.flushBatch(chunk, reporter));
        }
    }

    /** Stop accepting, drain everything, wait for the flusher to finish. */
    @Override
    public void close() {
        running = false;
        try {
            flusher.join();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
