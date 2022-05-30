
from kafka import KafkaConsumer
import time
import os
import json
import sys
import random

def main(cert_folder, topic_name, group_id):

    consumer = KafkaConsumer(
            topic_name,
            bootstrap_servers=os.environ["KAFKA_HOSTNAME"] + ':' + os.environ["KAFKA_PORT"],
            security_protocol='SSL',
            ssl_cafile=cert_folder+'/ca.pem',
            ssl_certfile=cert_folder+'/service.cert',
            ssl_keyfile=cert_folder+'/service.key',
            value_deserializer=lambda v: json.loads(v),
            key_deserializer=lambda v: v,
            auto_offset_reset='earliest',
            enable_auto_commit=True,
            group_id=group_id,
        )
  
    while True:

        for msg in consumer:
            print('Receiving: {}'.format(msg.value['payload']['after']))

if __name__ == '__main__':
    if len(sys.argv) != 4:
        print("consume.py cert_folder topic_name group_id")
        exit()

    main(cert_folder=sys.argv[1], topic_name=sys.argv[2], group_id=sys.argv[3])