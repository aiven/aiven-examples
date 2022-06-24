import argparse
import random
from string import ascii_uppercase

import time
from loguru import logger

from db import create_db_pool

db_pool = create_db_pool(open=True, autocommit=True)

count = 0


def create_table(conn, table_name, drop_table=False):
    try:
        if drop_table:
            conn.execute(f"DROP TABLE IF EXISTS {table_name}")
        conn.execute(f"CREATE TABLE IF NOT EXISTS {table_name} (id serial PRIMARY KEY, data varchar);")
    except Exception as e:
        logger.error(e)


def debezium_slot_status(debezium_slot_name):
    with db_pool.connection() as conn:
        try:
            cursor = conn.execute("""
                SELECT
                    slot_name,
                    active,
                    restart_lsn,
                    sum(pg_catalog.pg_wal_lsn_diff(pg_catalog.pg_current_wal_lsn(), restart_lsn)::BIGINT)::BIGINT AS bytes_diff
                FROM pg_catalog.pg_replication_slots
                GROUP BY slot_name, active, restart_lsn
                """)
            active = False
            exists = False
            for record in cursor:
                if record[0] == debezium_slot_name:
                    # check for slot active state
                    logger.info(f'{record}')
                    active = record[1]
                    exists = True
                    break
            return {
                'active': active,
                'exists': exists
            }

        except Exception:
            logger.error("Failed to fetch Debezium slot status...")
            raise


def main(table_name):
    with db_pool.connection() as conn:
        create_table(conn, table_name)
    while True:
        try:
            query = f"INSERT INTO {table_name} (data) VALUES (%s);"
            random_data = "".join(random.choice(ascii_uppercase) for _ in range(20))
            with db_pool.connection() as conn:
                if debezium_slot_status('debezium')['exists']:
                    conn.execute(query, params=[random_data])
                else:
                    t = 5
                    logger.warning(f"Slot does not exist. Trying again in {t} seconds")
                    time.sleep(t)
            time.sleep(1)
        except Exception as e:
            logger.error(e)
            time.sleep(5)


if __name__ == "__main__":
    # parser = argparse.ArgumentParser()
    # parser.add_argument(
    #     "--table",
    #     type=str,
    #     required=True,
    #     help="The table into which we write test data."
    # )
    # args = parser.parse_args()
    # main(args.table)
    main("public.all_datatypes")
