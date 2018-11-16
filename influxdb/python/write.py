# Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/
from influxdb import InfluxDBClient

import datetime

uri = "https+influxdb://avnadmin:<your password here>@influx-3b8d4ed6-myfirstcloudhub.aivencloud.com:15193/defaultdb"
client = InfluxDBClient.from_dsn(uri, timeout=3.0, ssl=True)

json_body = [
    {
        "measurement": "cpu_load_short",
        "tags": {
            "host": "testnode",
        },
        "time": datetime.datetime.now().isoformat(),
        "fields": {
            "value": 0.95
        }
    }
]

client.write_points(json_body)
print(json_body, "written to influxdb")
