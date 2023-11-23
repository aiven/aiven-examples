#include <kafka/KafkaProducer.h>

extern const kafka::Properties props({
                    {"bootstrap.servers", {getenv("KAFKA_BROKER_LIST")}},
                    {"security.protocol", {getenv("SECURITY_PROTOCOL")}},
                    {"ssl.ca.location"  , {getenv("SSL_CA_LOCATION")}},
                    {"ssl.certificate.location" , {getenv("SSL_CERTIFICATE_LOCATION")}},
                    {"ssl.key.location"         , {getenv("SSL_KEY_LOCATION")}}
});

extern const kafka::Topic topic = getenv("KAFKA_TOPIC");