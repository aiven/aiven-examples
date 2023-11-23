#include <kafka/KafkaProducer.h>

#include <cstdlib>
#include <iostream>
#include <string>
#include <signal.h>

#include "config.hh"

std::atomic_bool running = {true};

void stopRunning(int sig) {
    if (sig != SIGINT) return;

    if (running) {
        running = false;
    } else {
        // Restore the signal handler, -- to avoid stuck with this handler
        signal(SIGINT, SIG_IGN); // NOLINT
    }
}

int main()
{
    using namespace kafka;
    using namespace kafka::clients::producer;

    // Create a producer
    KafkaProducer producer(props);

    // Use Ctrl-C to terminate the program
    signal(SIGINT, stopRunning);    // NOLINT

    while (running) {
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
                running = false;
            }
        };

        if (running && !line.empty()) {
            // Send a message
            producer.send(record, deliveryCb);
            // Close the producer explicitly(or not, since RAII will take care of it)
            producer.close();
        }
        else {
            break;
        }
    }
}

