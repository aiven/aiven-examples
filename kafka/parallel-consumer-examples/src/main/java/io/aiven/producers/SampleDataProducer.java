package io.aiven.producers;

import io.aiven.config.AppConfig;
import io.aiven.models.Payload;
import org.apache.kafka.clients.producer.Callback;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.clients.producer.RecordMetadata;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.List;
import java.util.Random;
import java.util.concurrent.TimeUnit;
import java.util.stream.IntStream;

public class SampleDataProducer {
    private static final Logger logger
            = LoggerFactory.getLogger(SampleDataProducer.class);

    private static final Random random = new Random();
    private static int keyspaceSize = AppConfig.keyspaceSizeUpper;

    public static void main(String[] args) throws InterruptedException {
        var properties = AppConfig.getProducerProps();

        logger.info("Starting Kafka Producer with configs ...");
        properties.forEach((key, value) -> {
            System.out.printf("\t%s: %s%n", key, value);
        });

        KafkaProducer<String, Payload> producer = new KafkaProducer(properties);

        var messagesSoFar = 1;

        var t0 = System.currentTimeMillis();
        for (int i = 0; i < AppConfig.totalMessagesToSent; i++) {
            var t1 = System.currentTimeMillis();
            List<ProducerRecord<String, Payload>> records =
                    IntStream
                            .range(0, AppConfig.messagesPerSecond)
                            .mapToObj(SampleDataProducer::createRecord)
                            .toList();

            for (ProducerRecord<String, Payload> record: records) {
                producer.send(record);
                messagesSoFar += 1;
                if (messagesSoFar % 500 == 0) {
                    if (keyspaceSize == AppConfig.keyspaceSizeUpper) {
                        keyspaceSize = random.nextInt(5) + 1;
                    } else {
                        keyspaceSize = AppConfig.keyspaceSizeUpper;
                    }
                    logger.info("Keyspace now is: '{}'.", keyspaceSize);
                }
            }
            var t2 = System.currentTimeMillis();
            logger.info("Sending '{}' messages/s - '{}'Kb/s", AppConfig.messagesPerSecond, (400 * AppConfig.messagesPerSecond) / 1000);
            logger.info("Total so far: {}", messagesSoFar);
            Thread.sleep(1000 - (t2 - t1));
        }
        logger.info("Total messages sent '{}' in {} seconds.", AppConfig.totalMessagesToSent, TimeUnit.MILLISECONDS.toSeconds(System.currentTimeMillis() - t0));
        logger.info("Closing resources ...");
        producer.close();
    }

    private static ProducerRecord<String, Payload> createRecord(int index) {
        String key = String.valueOf(random.nextInt(keyspaceSize));
        // Create a 400bytes message
        byte[] payload = new byte[AppConfig.payloadSize];
        return new ProducerRecord<String, Payload>(AppConfig.TEST_TOPIC, key, new Payload(new String(payload)));
    }

    private static Callback producerCallback(ProducerRecord<String, Payload> record) {
        return new Callback() {
            @Override
            public void onCompletion(RecordMetadata metadata, Exception exception) {
                if (exception != null) {
                    logger.warn("Got an exception while processing record: {}. {}", record, exception.getMessage());
                } else {
                    logger.info("""
                            Successfully processed record - Key: {}\t| Value: {}\t| Offset: {}\t| Partition: {}
                            """, record.key(), record.value(), metadata.offset(), metadata.partition());
                }
            }
        };
    }
}
