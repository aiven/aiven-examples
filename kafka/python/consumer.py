# Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/
from kafka import KafkaConsumer

consumer = KafkaConsumer(
    bootstrap_servers=["kafka-example.avns.net:11111"],
    auto_offset_reset='earliest',
    security_protocol="SSL",
    ssl_cafile="ca.pem",
    ssl_certfile="service.cert",
    ssl_keyfile="service.key",
    consumer_timeout_ms=1000,
)

consumer.subscribe(['my_topic'])
for message in consumer:
    print(message.value)

consumer.close()
