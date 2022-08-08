# Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/
from kafka import KafkaConsumer


def consumer_example(service_uri, ca_path, cert_path, key_path):
    consumer = KafkaConsumer(
        bootstrap_servers=service_uri,
        auto_offset_reset='earliest',
        security_protocol="SSL",
        ssl_cafile=ca_path,
        ssl_certfile=cert_path,
        ssl_keyfile=key_path,
        consumer_timeout_ms=1000,
        group_id="comer",
    )

    print(consumer.partitions_for_topic("python_example_topic"))

    consumer.subscribe(['test-topic'])
    while True:
        messages_lists = consumer.poll(max_records=10)
        for message_list in messages_lists.values():
            for message in message_list:
                print(message.value.decode('utf-8'))
    consumer.close()
