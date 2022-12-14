import pandas as pd
import json
import os
import re
import requests
from kafka import KafkaProducer

import config


def kafka_producer():
    return KafkaProducer(
        # api_version=(0, 10, 2)
        api_version_auto_timeout_ms=config.KAFKA_TIMEOUT,
        bootstrap_servers=config.KAFKA_URI,
        security_protocol=config.KAFKA_SECURITY_PROTOCOL,
        ssl_cafile=config.KAFKA_SSL_CA,
        ssl_certfile=config.KAFKA_SSL_CERT,
        ssl_keyfile=config.KAFKA_SSL_KEY,
        key_serializer=str.encode,
        value_serializer=lambda v: json.dumps(v).encode('utf-8'),
    )


def df2json(df, arr_columns, id_col):
    """Convert the dataframe to json file that is ready to be uploaded to the server"""
    """if file_name in os.listdir(file_loc):
        os.remove(file_loc + file_name)"""
    producer = kafka_producer()
    message_batch_size = 100
    for i, row in df.iterrows():

        message_key = str(row[id_col])
        d2 = {}
        for col in df.columns:
            if col != id_col and col in arr_columns:
                d2[col] = row[col]

        producer.send(config.KAFKA_TOPIC_SOURCE, key=message_key, value=d2)
        if i % message_batch_size == 0:
            producer.flush()

    producer.flush()

def main():
    df = pd.read_csv('../WMT_Grocery_202209.csv')
    arr_columns_to_index = ['DEPARTMENT', 'CATEGORY', 'BREADCRUMBS', 'SKU', 'PRODUCT_URL',
                            'PRODUCT_NAME', 'BRAND', 'PRICE_RETAIL', 'PRICE_CURRENT']
    df2json(df, arr_columns_to_index, 'index')


if __name__ == '__main__':
    main()
