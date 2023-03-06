#!/bin/bash

usage() {
    printf "dd-custom-metrics.sh sends custom metrics to datadog.\nUsage: ./dd-custom-metrics.sh METRICS-NAME VALUE\n" 1>&2; exit 1;
}

if [ "$#" -ne 2 ]; then
    usage;
fi

# DD_API_KEY="API-KEY"
# SERVICE="AIVEN-SERVICE"
# PROJECT="AIVEN-PROJECT"
METRIC=$1
VALUE=$2
NOW="$(date +%s)"

echo "${METRIC}"
echo ${NOW}

curl -X POST "https://api.datadoghq.com/api/v2/series" \
-s \
-H "Accept: application/json" \
-H "Content-Type: application/json" \
-H "DD-API-KEY: ${DD_API_KEY}" \
-d @- << EOF
{
  "series": [
    {
      "metric": "${METRIC}",
      "points": [
        {
          "timestamp": ${NOW},
          "value": "${VALUE}"
        }
      ],
      "resources": [
        {
          "name": "${SERVICE}",
          "type": "aiven-service"
        },
        {
          "name": "${PROJECT}",
          "type": "aiven-project"
        }

      ]
    }
  ]
}
EOF
