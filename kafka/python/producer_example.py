# Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/
from kafka import KafkaProducer


def producer_example(service_uri, ca_path, cert_path, key_path):
    producer = KafkaProducer(
        bootstrap_servers=service_uri,
        security_protocol="SSL",
        ssl_cafile=ca_path,
        ssl_certfile=cert_path,
        ssl_keyfile=key_path,
    )

    for i in range(1, 4):
        message = "message number {}".format(i)
        print("Sending: {}".format(message))
        producer.send("python_example_topic", message.encode("utf-8"))

    # Wait for all messages to be sent
    producer.flush()
