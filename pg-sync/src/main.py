import orjson
import time
from loguru import logger

from utilities import make_ssl_context, create_insert_statement, create_update_statement, create_delete_statement, \
    cast_values, create_consumer
from env import KAFKA_BROKER, CDC_TOPIC_NAME, ROW_IDENTIFIER
from db import create_db_pool

retry = 2
ssl_context = make_ssl_context(cafile_path='certs/ca.pem',
                               certfile_path='certs/service.cert',
                               keyfile_path='certs/service.key')

consumer = create_consumer(CDC_TOPIC_NAME,
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

for msg in consumer:
    while True:
        try:
            if msg.value is None:
                # After all deletions a null tombstone event is created (for Kafka compaction)
                break
            change = orjson.loads(msg.value)
            logger.info(f'{change}')

            before, after = change['before'], change['after']
            if before and after:
                # Update
                a_keys, a_values = after.keys(), after.values()
                b_keys, b_values = before.keys(), before.values()
                try:
                    with db_pool.connection() as conn:
                        query = create_update_statement(change['source']['table'], before, after)
                        a_casted_values = cast_values(a_keys, a_values)
                        if ROW_IDENTIFIER:
                            keys = ROW_IDENTIFIER
                            values = [before[k] for k in keys]
                        else:
                            keys = b_keys
                            values = b_values
                        b_casted_values = cast_values(keys, values)
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
                try:
                    with db_pool.connection() as conn:
                        query = create_insert_statement(change['source']['table'], after)
                        casted_values = cast_values(keys, values)
                        logger.info(query)
                        logger.info(casted_values)
                        conn.execute(query, params=casted_values)
                except Exception as e:
                    logger.error(f'{e}')
                    raise
            else:
                # Delete
                keys, values = before.keys(), before.values()
                try:
                    with db_pool.connection() as conn:
                        query = create_delete_statement(change['source']['table'], before)
                        if ROW_IDENTIFIER:
                            keys = ROW_IDENTIFIER
                            values = [before[k] for k in keys]
                        casted_values = cast_values(keys, values)
                        logger.info(query)
                        logger.info(casted_values)
                        conn.execute(query, params=casted_values)
                except Exception as e:
                    logger.error(f'{e}')
                    raise
        except Exception as e:
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
