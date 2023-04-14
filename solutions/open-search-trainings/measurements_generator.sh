#!/bin/bash

for h in {1..72}; do
 for room in {1..50}; do
   timestamp=$(date -u -v-72H -v"+${h}H" +"%Y-%m-%dT%H:%M:%S.000Z")
   sensor_id="room_${room}_sensor"
   location="Room ${room}"
   temperature=$(echo "scale=1; $((RANDOM % 10 + 18)).$((RANDOM % 10))" | bc)
   humidity=$((RANDOM % 50 + 30))
   co2_level=$((RANDOM % 500 + 500))

   json_object=$(cat <<EOF
{
 "@timestamp": "$timestamp",
 "sensor_id": "$sensor_id",
 "location": "$location",
 "temperature": $temperature,
 "humidity": $humidity,
 "co2_level": $co2_level
}
EOF
)
   echo $json_object | kcat -F kcat.config -P -t measurements
 done
done

