#!/bin/bash

usage() { 
    printf "service-ipwatch checks ip and port for aiven service.\nUsage: ./service-ipwatch.sh hostname port \n" 1>&2; exit 1; 
}

if [ "$#" -ne 2 ]; then
    usage;
fi

AVN_HOST=$1
AVN_PORT=$2
while [ 1 ]; do echo `date` - `dig +short $AVN_HOST` `nc -vz $AVN_HOST $AVN_PORT 2>&1 | awk '{print $NF}'` && sleep 1; done