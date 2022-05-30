import time
import os
import sys
import random
import psycopg2
import logging
import argparse

# Logger
logger = logging.getLogger(os.path.basename(__file__))

def produce(user, password, host, port, database, nb_seconds, nb_per_second):
    connection = None
    cursor = None
    try:
        connection = psycopg2.connect(user=user,
                                    password=password,
                                    host=host,
                                    port=port,
                                    database=database,
                                    sslmode='require')

        t = 0
        while t < nb_seconds :
            cursor = connection.cursor()
            
            postgres_insert_query = """ INSERT INTO cpu_usage(hostname, cpu, usage, occurred_at) values(%s,%s,%s,NOW()::timestamp)"""
            records_to_insert = [
                (
                'cluster' + str(random.randint(0,50)), 
                random.randint(1,4),
                random.random()*80+20
                ) for i in range(0, nb_per_second) ]
            cursor.executemany(postgres_insert_query, records_to_insert)
            connection.commit()
            
            logger.info("%d records loaded", cursor.rowcount)

            time.sleep(1)
            t += 1

    except (Exception, psycopg2.Error) as error:
        logger.error("Failed to insert demo data", error)

    finally:
        if cursor:
            cursor.close()
        if connection:
            connection.close()


if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO)

    parser = argparse.ArgumentParser(description="CPU usage simulator.")
    parser.add_argument("-t", "--time", default=5, type=int, help="Nb seconds to run")
    parser.add_argument("-v", "--velocity", default=1, type=int, help="Nb of measurements per second.")
    opts = parser.parse_args(sys.argv[1:])

    produce(
        user=os.environ["PG_USER"], 
        password=os.environ["PG_PASSWORD"], 
        host=os.environ["PG_HOST"], 
        port=os.environ["PG_PORT"], 
        database=os.environ["PG_DATABASE_NAME"],
        nb_seconds=int(opts.time), 
        nb_per_second=int(opts.velocity)
    )
