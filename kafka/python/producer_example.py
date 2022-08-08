# Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/
import time

from kafka import KafkaProducer


def producer_example(service_uri, ca_path, cert_path, key_path):
    print(service_uri)
    print(ca_path)
    print(cert_path)
    print(key_path)
    producer = KafkaProducer(
        bootstrap_servers=service_uri,
        security_protocol="SSL",
        ssl_cafile=ca_path,
        ssl_certfile=cert_path,
        ssl_keyfile=key_path,
        linger_ms=400,
    )

    try:
        i = 0
        while True:
            i += 1
            message = "".join(1000 * f"message number {i}")
            if i % 1000 == 0:
                print("Sending: {}".format(i))
                producer.flush()
            producer.send("titi", message.encode("utf-8"))

    finally:
        # Wait for all messages to be sent
        producer.flush()
