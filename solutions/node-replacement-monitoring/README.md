## Monitoring node replacements

The `nodes_monitor.sh` script monitors node replacements and pushes metrics to an InfluxDB service. It collects the current number of service nodes and the ID of the latest node as the `node_count` and `latest_node_id` metrics, respectively. Then it writes these metrics to an InfluxDB service.

Use environment variables to set the required parameters or uncomment them in the `CONFIGURATION` segment.
|variable|description|
|-|-|
|`PROJECT_NAME`|Aiven project name|
|`SERVICE_NAME`|Aiven service name|
|`AIVEN_TOKEN`|Aiven access token|
|`INFLUX_HOSTNAME`|Aiven for InfluxDB service hostname (host:port)|
|`INFLUX_DB`|Aiven for InfluxDB service database name|
|`INFLUX_AUTH`|Aiven for InfluxDB service credentials (username:password)|
|`INFLUX_TAGS`|Aiven for InfluxDB tags|
|`SLEEP_DELAY`|Delay between checks|


The script requirements:
* `curl` - command-line tool for transferring data using various network protocols
* `jq` - command-line JSON processor
* M3DB or InfluxDB service

One way to run the script is to package it and run it as a Docker image:
```
docker build -t aiven_nodes_monitor .
docker run -d \
    --restart=unless-stopped \
    --name=nodes_monitor \
    -e PROJECT_NAME="my-project" \
    -e SERVICE_NAME="kafka_1234" \
    -e AIVEN_TOKEN='my_aiven_token' \
    -e INFLUX_HOSTNAME="influx_4321.aivencloud.com:18291" \
    -e INFLUX_DB="defaultdb" \
    -e INFLUX_AUTH="avnadmin:my_password" \
    -e SLEEP_DELAY=30 \
    aiven_nodes_monitor
```
