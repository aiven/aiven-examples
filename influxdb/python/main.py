#!/usr/bin/env python3
import argparse

from datetime import datetime
from influxdb import InfluxDBClient


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--url',
                        help="InfluxDB URL from Aiven console in the form "
                             "https+influxdb://<username>:<password>@<host>:<port>/<database>",
                        required=True)
    args = parser.parse_args()
    client = InfluxDBClient.from_dsn(args.url, timeout=3.0, ssl=True)

    # Write our sample data
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
    client.write_points(json_body)

    # Read it back again
    result = client.query('select value from cpu_load_short;')
    print(f"Result: {result}")


if __name__ == '__main__':
    main()
