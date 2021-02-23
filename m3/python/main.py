#!/usr/bin/env python3
# Copyright (c) 2020 Aiven, Helsinki, Finland. https://aiven.io/

import argparse
from datetime import datetime
import json
import os
import time
import logging

import requests

from aiven.client import AivenClient
from aiven.client.client import Error as AivenClientError
from influxdb import InfluxDBClient


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", help="M3 Service Host", required=True)
    parser.add_argument("--port", type=int, help="M3 Service Port", required=True)
    parser.add_argument("--user", help="M3 Service User", default="avnadmin")
    parser.add_argument("--password", help="M3 Service Password", required=True)
    parser.add_argument("--project", help="Aiven Project Name", default=os.environ.get("AIVEN_TEST_PROJECT", "test"))
    parser.add_argument("--m3db", help="M3DB Service Name", default="m3db-latest-business-8")
    parser.add_argument("--m3aggregator", help="M3 Aggregator Service Name", default="m3aggregator-latest-business-8")

    args = parser.parse_args()

    client = AivenClient(base_url=os.environ.get("AIVEN_WEB_URL", "https://api.aiven.io"))
    client.set_auth_token(os.environ["AIVEN_AUTH_TOKEN"])

    log = logging.getLogger(__name__)

    def create_integration(*, source, destination, integration):
        try:
            log.info(f"Creating {integration} integration from {source} to {destination}")
            client.create_service_integration(
                dest_service=destination,
                integration_type=integration,
                project=args.project,
                source_service=source,
            )
        except AivenClientError as ex:
            message = ex.response.json()["message"]
            log.warning(f"Error creating {integration} integration from {source} to {destination}")
            acceptable_errors = ("Service integration already exists", "Only 1 integration(s) of this type allowed per service")
            if not (ex.status == 409 and message in acceptable_errors):
                raise

    create_integration(source=args.m3db, destination=args.m3aggregator, integration="m3aggregator")

    client = InfluxDBClient(host=args.host,
                            port=args.port,
                            username=args.user,
                            password=args.password,
                            database="default",
                            ssl=True,
                            path='/api/v1/influxdb')

    json_body = [
        {
            "measurement": "cpu_load_short",
            "tags": {
                "host": "testnode",
            },
            "time": datetime.now().isoformat(),
            "fields": {
                "value": 0.95
            }
        }
    ]
    print(client.write_points(json_body))


if __name__ == "__main__":
    main()
