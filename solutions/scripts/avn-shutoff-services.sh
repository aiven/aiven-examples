#!/bin/bash

# before running your avn cli needs to be authenticated
# and the environment should have jq installed https://stedolan.github.io/jq/

USAGE="usage: --project <YOUR_AIVEN_PROJECT>"
if (( $# == 0 ))
then
        echo $USAGE
        exit 1
fi

while [ $# -gt 0 ]; do
    case $1 in
    --project)
        shift && PROJECT="$1"
        ;;
    *)
        echo "unknown argument $1"
        exit 1
        ;;
    esac
    shift
done 

echo "Shutting down Aiven services for $PROJECT"

#get list of services
services=$(avn service list --project $PROJECT --json | jq )

function stop_service() {
    echo "Shutting down service [$1]"
    output=$(avn service update --power-off $1) 
    echo $output
}

jq -c '.[]' <<<$services | while read s; do
    service_name=$(jq -r '.service_name' <<< $s)
    state=$(jq -r '.state' <<< $s)
    if [ $state = "RUNNING" ]; then
        stop_service $service_name $state
    else 
        echo "$service_name is $state"
    fi
done
