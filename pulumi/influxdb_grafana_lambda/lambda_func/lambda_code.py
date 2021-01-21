import os
import json
import random
import urllib3
from influxdb import InfluxDBClient


# Lambda function endpoint
def lambda_handler(event, context):
    # Get the URL (including username and password) of the provisioned service instance
    uri = os.environ['SERVICE_URI']

    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    client = InfluxDBClient.from_dsn(uri, timeout=1.0, ssl=True)

    # Write our sample data
    json_body = [
        {
            "measurement": "outside_temp",
            "fields": {"value": random.uniform(-30, 130)}
        }
    ]

    try:
        client.write_points(json_body)
        return True
    except:
        print('Failed to send metrics to influxdb') 
        return False

