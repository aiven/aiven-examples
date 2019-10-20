#!/usr/bin/env python3
# Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/

import argparse
import redis


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--host', help="Redis host", required=True)
    parser.add_argument('--port', help="Redis port", required=True, type=int)
    parser.add_argument('--password', help="Redis password", required=True)
    args = parser.parse_args()

    client = redis.StrictRedis(
        host=args.host,
        port=args.port,
        password=args.password,
        ssl=True
    )
    client.ping()
    client.set('exampleKey', 'exampleValue')

    value = client.get("exampleKey")
    print("The value for 'exampleKey' is: ''%s'" % value)


if __name__ == "__main__":
    main()
