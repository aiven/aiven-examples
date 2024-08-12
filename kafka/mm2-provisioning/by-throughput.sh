#!/bin/bash

bootstrap_servers=$1
high_throughput_threshold=80  # Adjust this threshold as needed

# Get list of topics
topics=$(kafka-topics.sh --bootstrap-server "$bootstrap_servers" --list)

# Gather topic and partition data
topic_data=()
for topic in $topics; do
    partitions=$(kafka-topics.sh --bootstrap-server "$bootstrap_servers" --describe --topic "$topic" | grep -oP 'PartitionCount:\s+\K\d+')
    throughput=85  # Replace with your actual throughput data gathering mechanism
    topic_data+=("{\"topic\": \"$topic\", \"partitions\": $partitions, \"throughput\": $throughput}")
done

# Sort topics by throughput (descending order)
sorted_topics=$(printf '%s\n' "${topic_data[@]}" | jq -s 'sort_by(.throughput) | reverse')

# Assign partitions
cluster_count=2 # Set to number of MM2 Clusters
assignments=()

for ((i=0; i<$cluster_count; i++)); do assignments[i]=""; done
current_cluster=0

while IFS= read -r data; do
    topic=$(echo "$data" | jq -r '.topic')
    partitions=$(echo "$data" | jq '.partitions')
    throughput=$(echo "$data" | jq '.throughput')

    # Balance based on throughput and partition count
    if (( throughput >= high_throughput_threshold )); then
        # Assign to the cluster with fewer partitions
        current_cluster=$(IFS=$'\n'; printf '%s\n' "${assignments[@]}" | awk '{print length($0), NR - 1}' | sort -n | head -n 1 | awk '{print $2}')
    else
        # Assign to the cluster with lower total throughput
        current_cluster=$(IFS=$'\n'; printf '%s\n' "${assignments[@]}" | awk '{print length($0) + gsub("throughput", "", $0), NR - 1}' | sort -n | head -n 1 | awk '{print $2}')
    fi

    for ((partition=0; partition<$partitions; partition++)); do
        assignments[current_cluster]+="{\"topic\": \"$topic\", \"partition\": $partition},"
    done
done <<< "$sorted_topics"

# Output results
for ((i=0; i<$cluster_count; i++)); do
    echo "Cluster $i:"
    echo "[${assignments[i]%,}]" | jq
    echo
done