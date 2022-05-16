import io
import json
import struct

import time

import requests
from loguru import logger
from fastavro import schemaless_reader
from psycopg.errors import UniqueViolation
from requests.auth import HTTPBasicAuth

from utilities import make_ssl_context, create_insert_statement, create_update_statement, create_delete_statement, \
    cast_values, create_consumer, find_row_identifier, create_avro_consumer
from env import KAFKA_BROKER, CONFIG
from db import create_db_pool

REGISTRY_HOST = 'https://replicator-kafka-akahn-demo.aivencloud.com'
REGISTRY_PORT = '24282'
REGISTRY_USER = 'avnadmin'
REGISTRY_PW = 'AVNS_nDfrgSW10WbT16R'
SCHEMA_NAME = 'replicator.public.all_datatypes-value'

START_BYTE = 0x0
HEADER_FORMAT = ">bI"
HEADER_SIZE = 5

retry = 2
ssl_context = make_ssl_context(cafile_path='certs/ca.pem',
                               certfile_path='certs/service.cert',
                               keyfile_path='certs/service.key')

topics = [v["topic"] for v in CONFIG.values()]

consumer = create_consumer(topics,
                           [KAFKA_BROKER],
                           ssl_context,
                           group_id='cdc',
                           session_timeout_ms=180000,
                           heartbeat_interval_ms=60000,
                           metadata_max_age_ms=50000,
                           max_poll_interval_ms=300000,
                           request_timeout_ms=305000,
                           auto_offset_reset='earliest',
                           enable_auto_commit=False)

db_pool = create_db_pool(open=True, autocommit=True)


def get_schemas():
    """Get all available schemas"""
    r = requests.get(url=f'{REGISTRY_HOST}:{REGISTRY_PORT}/subjects',
                     auth=HTTPBasicAuth(REGISTRY_USER, REGISTRY_PW))

    return r.json()


def get_schema_versions(schema_name_):
    """Get all versions of a schema"""
    r = requests.get(url=f'{REGISTRY_HOST}:{REGISTRY_PORT}/subjects/{schema_name_}/versions',
                     auth=HTTPBasicAuth(REGISTRY_USER, REGISTRY_PW))

    return r.json()


def get_schema_info(schema_name_, version):
    """Get the most recent version of a schema"""
    r = requests.get(url=f'{REGISTRY_HOST}:{REGISTRY_PORT}/subjects/{schema_name_}/versions/{version}',
                     auth=HTTPBasicAuth(REGISTRY_USER, REGISTRY_PW))

    return r.json()


def parse_avro(msg: bytes, schema_):
    with io.BytesIO(msg) as bio:
        byte_arr = bio.read(HEADER_SIZE)
        start_byte, schema_id = struct.unpack(HEADER_FORMAT, byte_arr)
        if start_byte != START_BYTE:
            raise ValueError("Start byte is %x and should be %x" % (start_byte, START_BYTE))
        record = schemaless_reader(bio, avro_schema)
        return record


versions = sorted(get_schema_versions(SCHEMA_NAME))
res = get_schema_info(SCHEMA_NAME, versions[-1])
avro_schema = json.loads(res["schema"])


for msg in consumer:
    while True:
        try:
            if msg.value is None:
                # After all deletions a None tombstone event is created (for Kafka compaction)
                break
            change = parse_avro(msg.value, avro_schema)
            # change = orjson.loads(msg.value)
            logger.info(f'{change}')

            before, after = change['before'], change['after']
            if before and after:
                # Update
                a_keys, a_values = after.keys(), after.values()
                b_keys, b_values = before.keys(), before.values()
                schema, table_name = change['source']['schema'], change['source']['table']
                try:
                    with db_pool.connection() as conn:
                        query = create_update_statement(schema, table_name, before, after)
                        a_casted_values = cast_values(a_keys, a_values, table_name)
                        row_identifier = find_row_identifier(table_name)
                        if row_identifier:
                            keys = row_identifier
                            values = [before[k] for k in keys]
                        else:
                            keys = b_keys
                            values = b_values
                        b_casted_values = cast_values(keys, values, table_name)
                        casted_values = a_casted_values + b_casted_values
                        logger.info(query)
                        logger.info(casted_values)
                        conn.execute(query, params=casted_values)
                except Exception as e:
                    logger.error(f'{e}')
                    raise
            elif before is None:
                # Insert
                keys, values = after.keys(), after.values()
                schema, table_name = change['source']['schema'], change['source']['table']
                try:
                    with db_pool.connection() as conn:
                        query = create_insert_statement(schema, table_name, after)
                        casted_values = cast_values(keys, values, table_name)
                        logger.info(query)
                        logger.info(casted_values)
                        conn.execute(query, params=casted_values)
                except Exception as e:
                    logger.error(f'{e}')
                    raise
            else:
                # Delete
                keys, values = before.keys(), before.values()
                schema, table_name = change['source']['schema'], change['source']['table']
                try:
                    with db_pool.connection() as conn:
                        query = create_delete_statement(schema, table_name, before)
                        row_identifier = find_row_identifier(table_name)
                        if row_identifier:
                            keys = row_identifier
                            values = [before[k] for k in keys]
                        casted_values = cast_values(keys, values, table_name)
                        logger.info(query)
                        logger.info(casted_values)
                        conn.execute(query, params=casted_values)
                except Exception as e:
                    logger.error(f'{e}')
                    raise
        except UniqueViolation as e:
            logger.error(f'Skipping record due to {e}')
            break
        except Exception as e:
            logger.error(f'failed due to {e}')
            logger.warning(f"Encountered a previous error. Retrying in {retry} seconds")
            time.sleep(retry)
        else:
            break
    while True:
        try:
            consumer.commit()
        except Exception as e:
            logger.error(e)
        else:
            break
