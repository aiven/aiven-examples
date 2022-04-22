#!/bin/bash

usage() { 
    printf "avn-pgdump create a read replica of postgresql to take a pg_dump then terminates the replica.\nUsage: ./avn-pgdump pgservice hostname port database username password \n" 1>&2;
    exit 1;
}

if [ "$#" -ne 6 ]; then
    usage;
fi

AVN_SERVICE=$1
AVN_HOST=$2
AVN_PORT=$3
AVN_REPLICA=${AVN_SERVICE}-replica
AVN_DB=$4

avn service create -t pg -p startup-4 $AVN_REPLICA --read-replica-for $AVN_SERVICE
if [ "$?" -ne 0 ]; then
    printf "ERROR: failed to create read replica ${AVN_REPLICA}\n" 1>&2;
    exit 1;
fi
avn service wait $AVN_REPLICA
PGDATABASE=$AVN_DB PGHOST=$AVN_HOST PGPORT=$AVN_PORT PGUSER=$5 PGPASSWORD=$6 pg_dump | gzip -9 > db-$(date +'%Y%m%d%H%M%S').gz
echo $AVN_REPLICA | avn service terminate $AVN_REPLICA