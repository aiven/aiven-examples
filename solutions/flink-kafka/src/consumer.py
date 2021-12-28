import config
from kafka import KafkaConsumer
import time

consumer = KafkaConsumer(
    config.KAFKA_TOPIC_SINK,
    auto_offset_reset="earliest",
    bootstrap_servers=config.KAFKA_URI,
    client_id=config.KAFKA_CONSUMER_CLIENT_ID,
    group_id=config.KAFKA_CONSUMER_GROUP_ID,
    security_protocol=config.KAFKA_SECURITY_PROTOCOL,
    ssl_cafile=config.KAFKA_SSL_CA,
    ssl_certfile=config.KAFKA_SSL_CERT,
    ssl_keyfile=config.KAFKA_SSL_KEY,
)

# Call poll twice. First call will just assign partitions for our
# consumer without actually returning anything

while 1:
    for _ in range(2):
        raw_msgs = consumer.poll(timeout_ms=config.KAFKA_TIMEOUT)
        for tp, msgs in raw_msgs.items():
            for msg in msgs:
                print(f'Received: {msg.value}')
    # keep polling every few seconds
    time.sleep(config.WAIT_TIME)

# Commit offsets so we won't get the same messages again

consumer.commit()