# Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/
from kafka import KafkaProducer

producer = KafkaProducer(
    bootstrap_servers="kafka-example.avns.net:11111",
    security_protocol="SSL",
    ssl_cafile="ca.pem",
    ssl_certfile="service.cert",
    ssl_keyfile="service.key",
)

for i in range(1, 4):
    message = "message number {}".format(i)
    print("Sending: {}".format(message))
    producer.send("my_topic", message.encode("utf-8"))

# Wait for all messages to be sent
producer.flush()
