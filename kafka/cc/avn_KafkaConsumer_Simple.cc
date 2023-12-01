#include <kafka/KafkaConsumer.h>

#include <cstdlib>
#include <iostream>
#include <signal.h>
#include <string>

#include "config.hh"

std::atomic_flag stop = ATOMIC_FLAG_INIT;

void signalHandler(int signum) {
    if (signum != SIGINT) return;

    stop.test_and_set();
    signal(SIGINT, SIG_IGN);
}

int main()
{
    using namespace kafka;
    using namespace kafka::clients::consumer;

    // Use Ctrl-C to terminate the program
    signal(SIGINT, signalHandler);

    // Create a consumer instance
    // No explicit consumer.close() is needed, RAII will take care of it
    KafkaConsumer consumer(props);

    // Subscribe to topics
    consumer.subscribe({topic});

    while (!stop.test()) {
        // Poll messages from Kafka brokers
        auto records = consumer.poll(std::chrono::milliseconds(100));

        for (const auto& record: records) {
            if (!record.error()) {
                std::cout << "Got a new message..." << std::endl;
                std::cout << "    Topic    : " << record.topic() << std::endl;
                std::cout << "    Partition: " << record.partition() << std::endl;
                std::cout << "    Offset   : " << record.offset() << std::endl;
                std::cout << "    Timestamp: " << record.timestamp().toString() << std::endl;
                std::cout << "    Headers  : " << toString(record.headers()) << std::endl;
                std::cout << "    Key   [" << record.key().toString() << "]" << std::endl;
                std::cout << "    Value [" << record.value().toString() << "]" << std::endl;
            } else {
                std::cerr << "Failed to consume message: [" << record.toString() << "]" << std::endl;
                break;
            }
        }
    }
}

