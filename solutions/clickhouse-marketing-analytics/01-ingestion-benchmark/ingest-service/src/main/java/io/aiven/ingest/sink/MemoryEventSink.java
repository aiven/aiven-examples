package io.aiven.ingest.sink;

import io.aiven.ingest.tier.rest.EventBuffer;
import io.aiven.ingest.tier.rest.EventDto;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

/**
 * The in-memory buffer behind POST /events (default mode). Kept for the
 * ladder benchmark and zero-dependency local runs; in-flight events die with
 * the app - the durability gap the valkey sink closes.
 */
@Component
@ConditionalOnProperty(name = "ingest.buffer", havingValue = "memory", matchIfMissing = true)
public class MemoryEventSink implements EventSink {

    // ObjectProvider keeps the buffer lazy (EventBuffer is final, so no @Lazy
    // proxy): benchmark-only runs never start the service flusher thread.
    private final ObjectProvider<EventBuffer> bufferProvider;

    public MemoryEventSink(ObjectProvider<EventBuffer> bufferProvider) {
        this.bufferProvider = bufferProvider;
    }

    @Override
    public boolean accept(EventDto event) {
        return bufferProvider.getObject().offer(event.toCampaignEvent());
    }

    @Override
    public long depth() {
        return bufferProvider.getObject().queueDepth();
    }
}
