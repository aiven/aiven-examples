#!/bin/bash

KAFKA_URI=$(terraform output -raw kafka_rest_uri)
BASIC_AUTH=$(echo -n "$(terraform output -raw kafka_rest_username):$(terraform output -raw kafka_rest_password)" | base64)
TOPIC="topic.public.test"
CONSUMER_GROUP="test_consumer_group"
CONSUMER_INSTANCE=$(uuidgen)

# Create a consumer
consumer_response=$(curl -s -X POST -H "Content-Type: application/vnd.kafka.v2+json" \
  --data "{
    \"name\": \"$CONSUMER_INSTANCE\",
    \"format\": \"binary\",
    \"auto.offset.reset\": \"earliest\",
    \"auto.commit.enable\": \"false\"
  }" \
  $KAFKA_URI/consumers/$CONSUMER_GROUP)

# Extract the base URI of the consumer instance
base_uri=$(echo $consumer_response | jq -r '.base_uri')

# Subscribe the consumer to test topic
curl -s -X POST -H "Content-Type: application/vnd.kafka.v2+json" -H "Authorization: Basic $BASIC_AUTH" \
  --data "{
    \"topics\": [\"$TOPIC\"]
  }" \
  $base_uri/subscription

# Read messages
messages=$(curl -s -X GET -H "Accept: application/vnd.kafka.binary.v2+json" -H "Authorization: Basic $BASIC_AUTH" $base_uri/records)
decoded_messages=$(echo "$messages" | jq -r '.[] | "\(.value | @base64d)"' | jq -s .)

echo $decoded_messages | jq

# Delete the consumer instance
curl -s -X DELETE -H "Content-Type: application/vnd.kafka.v2+json" -H "Authorization: Basic $BASIC_AUTH" $base_uri
