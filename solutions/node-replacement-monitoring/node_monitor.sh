#!/bin/bash

#############################
####### CONFIGURATION #######
#############################

# PROJECT_NAME="my-project"
# SERVICE_NAME="kafka_1234"
# AIVEN_TOKEN="my_aiven_token"
# INFLUX_HOSTNAME="influx_1234.aivencloud.com:18291"
# INFLUX_DB="defaultdb"
# INFLUX_AUTH="avnadmin:my_password"
# SLEEP_DELAY=30

#############################

INFLUX_TAGS=",service=$SERVICE_NAME"
if [ -z "$SLEEP_DELAY" ]
then
    $SLEEP_DELAY=30
fi

while true
do
    now=$(date +"%Y-%m-%d %H:%M:%S")
    echo "$now - Checking nodes"
    serviceJson=$(curl -sH "Authorization: bearer $AIVEN_TOKEN" https://api.aiven.io/v1/project/$PROJECT_NAME/service/$SERVICE_NAME)
    hasError=$(echo $serviceJson | jq '.errors')
    if [[ $hasError != null ]]; then
        errorMsg=$(echo $serviceJson | jq '.errors[0].message')
        echo "Error: $errorMsg"
    else
        nodes=$(echo $serviceJson | jq -r '[.service.node_states[].name] | join(" ")')
        code=$?
        if [ $code -eq 0 ]; then
            echo "Nodes: $nodes"
            latestNode=$(echo $nodes | grep -o '[0-9]*$')
            nodeCount=$(echo $nodes | wc -w | tr -d '[:blank:]')

            latestNodeStatus=$(curl -s -o /dev/null -w "%{http_code}" -XPOST "https://$INFLUX_HOSTNAME/api/v2/write?bucket=$INFLUX_DB" -H "Authorization: Token $INFLUX_AUTH" -d "latest_node_id$INFLUX_TAGS value=$latestNode")
            nodeCountStatus=$(curl -s -o /dev/null -w "%{http_code}" -XPOST "https://$INFLUX_HOSTNAME/api/v2/write?bucket=$INFLUX_DB" -H "Authorization: Token $INFLUX_AUTH" -d "node_count$INFLUX_TAGS value=$nodeCount")

            if [ $latestNodeStatus -ne 204 ]; then
                echo "Fail to insert latest node $latestNodeStatus"
            else
                echo "Inserted latest node: $latestNode"
            fi
            if [ $nodeCountStatus -ne 204 ]; then
                echo "Fail to insert node count $nodeCountStatus"
            else
                echo "Inserted node count: $nodeCount"
            fi
        fi
    fi
    sleep $SLEEP_DELAY
done
