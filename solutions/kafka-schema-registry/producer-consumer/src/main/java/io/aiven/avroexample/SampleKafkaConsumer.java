package io.aiven.avroexample;

import io.aiven.avro.example.ClickRecord;
import io.confluent.kafka.serializers.KafkaAvroDeserializer;
import io.confluent.kafka.serializers.KafkaAvroDeserializerConfig;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.ConsumerRecords;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.common.serialization.StringDeserializer;

import java.time.Duration;
import java.time.temporal.ChronoUnit;
import java.util.Collections;
import java.util.Properties;

import static io.aiven.avroexample.PropertiesInitialiser.initKafkaProperties;
import static io.aiven.avroexample.PropertiesInitialiser.readArg;

public final class SampleKafkaConsumer {
    public static void main(String[] args) {
        final Properties props = initProperties(args);
        String topic = readArg(args, "-t");
        if (topic == null) {
            throw new IllegalArgumentException("Please provide a valid topic with -t flag");
        }
        KafkaConsumer<String, ClickRecord> consumer = new KafkaConsumer<>(props);

        try {
            consumer.subscribe(Collections.singleton(topic));
            while (true) {
                ConsumerRecords<String, ClickRecord> records = consumer.poll(Duration.of(100, ChronoUnit.MILLIS));
                for(ConsumerRecord<String, ClickRecord> rec: records) {
                    System.out.println("Key: " + rec.key());
                    ClickRecord cRec = rec.value();
                    System.out.println("ClickRecord: ");
                    System.out.printf("\tSessionID: %s\n\tChannel: %s\n\tBrowser: %s\n\tCampaign: %s\n\tReferrer: %s\n\tIp: %s",
                            cRec.getSessionId(), cRec.getChannel(), cRec.getBrowser(), cRec.getCampaign(), cRec.getReferrer(), cRec.getIp());
                    System.out.println();
                }
                Thread.sleep(1000L);
            }
        } catch (Exception ex) {
            ex.printStackTrace();
        }
    }

    private static Properties initProperties(String[] args) {
        Properties props = initKafkaProperties(args);
        props.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        props.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, KafkaAvroDeserializer.class.getName());
        props.put(KafkaAvroDeserializerConfig.SPECIFIC_AVRO_READER_CONFIG, true);
        props.put(ConsumerConfig.GROUP_ID_CONFIG, "clickrecord-example-group");
        return props;
    }
}
