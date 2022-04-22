#!/bin/bash

usage() { 
    printf "avn-redisfork fork an existing redis service to take a backup and power-off the fork.\nUsage: ./avn-redisfork.sh service\n" 1>&2; exit 1; 
}

if [ "$#" -ne 1 ]; then
    usage;
fi

AVN_SERVICE=$1
AVN_FORK=${AVN_SERVICE}-fork

avn service create -t redis -p startup-4 ${AVN_FORK} -c service_to_fork_from=${AVN_SERVICE} 
if [ "$?" -eq 0 ]; then
    avn service wait ${AVN_FORK}
    echo "Initial backup in progress..."
    sleep 60
    until avn service update ${AVN_FORK} --power-off; do echo "waiting ${AVN_FORK} initial backup to be ready..." && sleep 5; done
    echo "${AVN_FORK} initial backup is ready and powered off!"
fi
