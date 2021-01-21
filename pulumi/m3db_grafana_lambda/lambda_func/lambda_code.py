import random
import os
import requests


# Lambda function endpoint
def lambda_handler(event, context):
    # Get the URL (including username and password) of the provisioned M3 instance
    uri = f"{os.environ['M3DB_URI']}/api/v1/influxdb/write"

    # The name of our data point to write along with a random value
    metric_name = "outside_temp"
    metric_value = random.uniform(-30, 130)

    # HTTP post to M3's InfluxDB write endpoint using the Line Protocol format
    r = requests.post(uri, data=f"{metric_name},tag=value value={metric_value}")
    print(r.status_code)
    return r.status_code == 204

