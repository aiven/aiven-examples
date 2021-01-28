import os
import math
import random
from psycopg2 import extras as pg_extras, connect as pg_connect
from faker import Faker


def get_row_count(service_uri):
    conn_string = os.getenv(service_uri)
    conn = pg_connect(conn_string)
    cursor = conn.cursor()
    cursor.execute('select count(*) from fake_orders;')
    count = cursor.fetchone()[0]
    cursor.close()
    print(f'Current row count in {service_uri}: {count}')


def generate_data(service_uri, records=1000):
    print(f'Inserting {records} records in {service_uri}')
    fake = Faker()

    conn_string = os.getenv(service_uri)
    conn = pg_connect(conn_string)
    cursor = conn.cursor()

    # Run database schema
    cursor.execute(open("schema.sql", "r").read())
    conn.commit()

    sql_template = "INSERT INTO fake_orders (name, addr, phone, user_agent, currency, isbn, qty, price)" \
        " VALUES (%s, %s, %s, %s, %s, %s, %s, %s);"

    batch = []
    for i in range(records):
        data = (fake.name(),
                fake.address(),
                fake.phone_number(),
                fake.user_agent(),
                fake.currency_code(),
                fake.isbn10(),
                random.uniform(1, i),
                math.ceil(random.uniform(0.9, 999.0) * 100) / 100
                )
        batch.append(data)

    pg_extras.execute_batch(cursor, sql_template, batch)
    conn.commit()


if __name__ == "__main__":
    generate_data("postgres_master_uri")
    get_row_count("postgres_master_uri")
    get_row_count("postgres_replica_uri")
