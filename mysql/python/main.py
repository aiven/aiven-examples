#!/usr/bin/env python3
# Copyright (c) 2020 Aiven, Helsinki, Finland. https://aiven.io/

import argparse
import pymysql

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", help="MySQL Service Host", required=True)
    parser.add_argument("--port", type=int, help="MySQL Service Port", required=True)
    parser.add_argument("--password", help="MySQL Service Password", required=True)
    parser.add_argument("--ca-file", help="MySQL CA file path", required=False)
    parser.add_argument("--timeout", type=int, help="MySQL Connect/Read/Write timeout", default=10)
    args = parser.parse_args()

    ssl_config = {"ca": args.ca_file} if args.ca_file else None

    connection = pymysql.connect(
        charset="utf8mb4",
        connect_timeout=args.timeout,
        cursorclass=pymysql.cursors.DictCursor,
        db="defaultdb",
        host=args.host,
        password=args.password,
        read_timeout=args.timeout,
        port=args.port,
        ssl=ssl_config,
        user="avnadmin",
        write_timeout=args.timeout,
    )

    try:
        cursor = connection.cursor()
        cursor.execute("SELECT DATABASE()")
        print(cursor.fetchone())
    finally:
        connection.close()


if __name__ == "__main__":
    main()
