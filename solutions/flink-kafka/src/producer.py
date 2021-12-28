import json
from faker import Faker
from kafka import KafkaProducer
from kafka.errors import KafkaError
from random import randrange
from os import environ as env
import config
from stockprovider import StockProvider
import time


def kafka_producer():
    return KafkaProducer(
        # api_version=(0, 10, 2)
        api_version_auto_timeout_ms=config.KAFKA_TIMEOUT,
        bootstrap_servers=config.KAFKA_URI,
        security_protocol=config.KAFKA_SECURITY_PROTOCOL,
        ssl_cafile=config.KAFKA_SSL_CA,
        ssl_certfile=config.KAFKA_SSL_CERT,
        ssl_keyfile=config.KAFKA_SSL_KEY,
        key_serializer=lambda v: json.dumps(v).encode('utf-8'),
        value_serializer=lambda v: json.dumps(v).encode('utf-8'),
    )


def main():
    # Creating a Faker instance and seeding to have the same results every time we execute the script
    fake = Faker()
    Faker.seed(4321)
    fake.add_provider(StockProvider)

    producer = kafka_producer()

    while 1:
        # sending 16 messages every 5 seconds
        for i in range(16):
            message, key = fake.produce_msg()
            # print(f'{key}:{message}')
            print(f'{json.dumps(message)}')
            producer.send(config.KAFKA_TOPIC_SOURCE, key=key, value=message)
            producer.flush(timeout=config.KAFKA_TIMEOUT)
        time.sleep(config.WAIT_TIME/2)


if __name__ == '__main__':
    main()