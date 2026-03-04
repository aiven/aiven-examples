#!/bin/bash

# Usage: ./create_topics_final.sh <input_file> <aiven_service_name>
INPUT_FILE=$1
SERVICE_NAME=$2

if [ -z "$INPUT_FILE" ] || [ -z "$SERVICE_NAME" ]; then
    echo "Usage: $0 <input_file> <aiven_service_name>"
    exit 1
fi

# Filter for the header lines in the 'describe' output
grep "^Topic:" "$INPUT_FILE" | grep "Configs:" | while read -r line; do

    # 1. Extract Topic Name (Position 2 for avn)
    TOPIC=$(echo "$line" | awk '{for(i=1;i<=NF;i++) if($i=="Topic:") print $(i+1)}')

    # 2. Extract Partition Count
    PARTITIONS=$(echo "$line" | sed -n 's/.*PartitionCount: \([0-9]*\).*/\1/p')

    # 3. Extract the numeric values for the specific properties
    # This pulls just the numbers from the 'key=value' strings
    MAX_MSG=$(echo "$line" | sed -n 's/.*max.message.bytes=\([0-9]*\).*/\1/p')
    RETENTION=$(echo "$line" | sed -n 's/.*retention.bytes=\([0-9]*\).*/\1/p')

    echo "----------------------------------------------------"
    echo "Processing: $TOPIC"

    # BUILD THE COMMAND
    # We use -c for the Kafka topic-level property 'max.message.bytes'
    # We use --retention-bytes for the retention property
    
    CMD=(avn service topic-create "$SERVICE_NAME" "$TOPIC" --partitions "$PARTITIONS" --replication 2)

    if [ -n "$RETENTION" ]; then
        CMD+=(--retention-bytes "$RETENTION")
    fi

    echo "Executing: ${CMD[*]}"
    "${CMD[@]}"

done
