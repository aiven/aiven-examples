package io.aiven.streams;

import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.streams.processor.TimestampExtractor;

import fi.saily.tmsdemo.DigitrafficMessage;

public class ObservationTimestampExtractor implements TimestampExtractor {

    @Override
    public long extract(ConsumerRecord<Object, Object> record, long partitionTime) {
        
        if (record.value() instanceof DigitrafficMessage) {
            DigitrafficMessage msg = (DigitrafficMessage) record.value();
            return msg.getMeasuredTime();
        }

        return 0;
    }
    
}
