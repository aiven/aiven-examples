#!/bin/bash

# uncomment ./dd-custom-metric.sh if sending metrics to datadog and export the following envirnment variables
# export DD_API_KEY="dd-key"; export SERVICE="aiven-service"; export PROJECT="aiven-project"; ./avn-dns-probe.sh FQDN

usage() { 
    printf "avn-dns-probe.sh checks for aiven service dns changes.\nUsage: ./avn-dns-probe.sh hostname \n" 1>&2; exit 1; 
}

if [ "$#" -ne 1 ]; then
    usage;
fi

AVN_HOST=$1
PROBE_INTERVAL=10

old_ip=$(dig +short $AVN_HOST | sort)
old_ip_num=$(echo ${old_ip} | wc -w | tr -d [:blank:])

[ ${old_ip_num} -eq 0 ] && printf "DNS resolution failed for ${AVN_HOST}.\n" && exit 1

while [ 1 ]; do
    new_ip=$(dig +short $AVN_HOST | sort)
    new_ip_num=$(echo ${new_ip} | wc -w | tr -d [:blank:])
    ## ./dd-custom-metric.sh aiven.node.count ${new_ip_num} > /dev/null

    if [[ ${old_ip_num} == ${new_ip_num} ]]; then
        if [[ ${old_ip} == ${new_ip} ]]; then
            # Same IP
            ## ./dd-custom-metric.sh aiven.node.recycle 0 > /dev/null
            printf "."
        else
            # IP change detected, add code/push notificaiton in this block.
            ## ./dd-custom-metric.sh aiven.node.recycle ${new_ip_num} > /dev/null
            printf "old_ip:\n[${old_ip}]:${ip_num}\n"
            printf "new_ip:\n<${new_ip}>:${new_ip_num}\n"
            printf "$(date) - IP changed!\n"
            old_ip=${new_ip}
        fi
    else
        [ ${new_ip_num} -eq 0 ] && printf "DNS resolution failed for ${AVN_HOST}.\n" && exit 1
        # node count changes (increase) during node replacement temporary, would goes back to the same number once stablized.
        # NOTE: node count changes would be permanent during plan change, in those case this script should be restarted to pick up new node count numbers.
        printf "$(date) - Node count changed, If this is a plan change please restart this script.\n"
    fi

    sleep ${PROBE_INTERVAL}
done
