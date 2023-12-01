#include <kafka/KafkaProducer.h>

#include <cstdlib>
#include <iostream>
#include <string>
#include <signal.h>

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
    using namespace kafka::clients::producer;

    // Create a producer
    KafkaProducer producer(props);

    // Use Ctrl-C to terminate the program
    signal(SIGINT, signalHandler);

    while (!stop.test()) {
        // Prepare a message
        std::cout << "Type anything and [enter] to produce a message or empty line to exit..." << std::endl;
        std::string line;
        std::getline(std::cin, line);

        const ProducerRecord record(topic, NullKey, Value(line.c_str(), line.size()));

        // Prepare delivery callback
        auto deliveryCb = [](const RecordMetadata& metadata, const Error& error) {
            if (!error) {
                std::cout << "Message delivered: " << metadata.toString() << std::endl;
            } else {
                std::cerr << "Message failed to be delivered: " << error.message() << std::endl;
                stop.test_and_set();
            }
        };

        if (!line.empty()) {
            // Send a message
            producer.send(record, deliveryCb);
            producer.flush();
        }
        else {
            break;
        }
    }
    // Close the producer explicitly(or not, since RAII will take care of it)
    producer.close();
}

