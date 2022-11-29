package io.aiven.consumers;

import io.aiven.config.AppConfig;
import io.aiven.models.Payload;
import io.confluent.parallelconsumer.ParallelConsumerOptions;
import io.confluent.parallelconsumer.ParallelStreamProcessor;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Collections;
import java.util.Random;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

public class ConsumerThread extends Thread {
    private final Logger logger
            = LoggerFactory.getLogger(ConsumerThread.class);
    private final String consumerThreadId;
    private AtomicInteger counter;

    public ConsumerThread(String consumerThreadId, AtomicInteger counter) {
        this.consumerThreadId = consumerThreadId;
        this.counter = counter;
    }

    @Override
    public void run() {
        logger.info("Starting consumer thread '{}'", consumerThreadId);
        var properties = AppConfig.getConsumerProps();

        KafkaConsumer<String, Payload> consumer = new KafkaConsumer<>(properties);

        ParallelConsumerOptions<String, Payload> consumerOptions =
                ParallelConsumerOptions.<String, Payload>builder()
                        .ordering(ParallelConsumerOptions.ProcessingOrder.KEY)
                        .maxConcurrency(1000)
                        .consumer(consumer)
                        .batchSize(5)
                        .commitMode(ParallelConsumerOptions.CommitMode.PERIODIC_CONSUMER_ASYNCHRONOUS)
                        .build();

        var eosStreamProcessor = ParallelStreamProcessor
                .createEosStreamProcessor(consumerOptions);

        eosStreamProcessor.subscribe(Collections.singletonList(AppConfig.MULTIPLE_PARTITIONS_TOPIC));
        Random rnd = new Random();


        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            logger.info("[Consumer-{}] Shutdown triggered. Closing resources ...", consumerThreadId);
            eosStreamProcessor.close();
        }));

        eosStreamProcessor.poll(context -> {
            logger.info("[Consumer-{}]: Batch contains '{}' records. Total messages processed so far {}", consumerThreadId, context.size(), counter.get());
            for (ConsumerRecord<String, Payload> record: context.getConsumerRecordsFlattened()) {
                try {
                    // Simulate a delay between 20 - 400 ms
                    Thread.sleep(rnd.nextInt(380) + 20);
                    counter.incrementAndGet();
                } catch (InterruptedException e) {
                    throw new RuntimeException(e);
                }
            }
        });
    }
}
