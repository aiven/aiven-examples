package io.aiven.consumers;

import io.aiven.config.AppConfig;

import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;

public class DataConsumer {
    public static void main(String[] args) {
        AtomicInteger counter = new AtomicInteger(0);

        List<Thread> consumers = new ArrayList<>();
        for (int i = 0; i < AppConfig.totalConsumerThreads; i ++) {
            consumers.add(
                    new ConsumerThread(String.valueOf(i), counter)
            );
        }

        consumers.forEach(Thread::start);

    }
}
