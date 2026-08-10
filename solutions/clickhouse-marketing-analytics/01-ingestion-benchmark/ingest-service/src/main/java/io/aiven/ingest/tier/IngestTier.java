package io.aiven.ingest.tier;

import io.aiven.ingest.bench.BenchmarkReporter;
import io.aiven.ingest.model.CampaignEvent;

import java.util.Iterator;

/**
 * One rung of the demo ladder. Every tier moves the same CampaignEvent payload
 * into the same campaign_events table - only the client technique changes.
 */
public interface IngestTier {

    /** Tier number, selected at runtime with --tier=0..5. */
    int tier();

    /** One-line description shown in logs and the benchmark label. */
    String description();

    /**
     * Drain {@code events} into ClickHouse, recording every flush and error on
     * {@code reporter}. Returns the number of rows successfully handed to the
     * server.
     */
    long ingest(Iterator<CampaignEvent> events, BenchmarkReporter reporter) throws Exception;
}
