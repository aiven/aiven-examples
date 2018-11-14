#!/usr/bin/env python3
# Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/
import argparse
import psycopg2


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--service-uri', help="Postgres Service URI (obtained from Aiven console)", required=True)
    args = parser.parse_args()

    db_conn = psycopg2.connect(args.service_uri)
    cursor = db_conn.cursor()

    cursor.execute("SELECT current_database()")
    result = cursor.fetchone()
    print("Successfully connected to: {}".format(result[0]))


if __name__ == "__main__":
    main()
