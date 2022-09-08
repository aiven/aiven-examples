#!/bin/bash

usage() {
  printf "\nAiven for ClickHouse CLI wrapper script\nQuickly query or load csvs into your service\n"
  printf "\n# clickhouse-client CLI\naiven-clickhouse.sh [-s|--service-name] clickhouse-service\n"
  printf "\n# load CSV into table\naiven-clickhouse.sh [-s|--service-name] clickhouse-service [-c|--csv-file] file.csv [-t|--table-name] table-name\n"
  exit 0
}

ARGS=()
DOCKER_CMD="docker run -it"
INSERT_QUERY=""

while [[ $# -gt 0 ]]
do
  case $1 in
    -s|--service-name)
      SERVICE="$2"
      shift
      shift
      ;;
    -c|--csv-file)
      CSV="$2"
      DOCKER_CMD=$(echo "cat $CSV|docker run -i")
      shift
      shift
      ;;
    -t|--table-name)
      TABLE="$2"
      INSERT_QUERY=$(echo "--query \"INSERT into ${TABLE} FORMAT CSV\"")
      shift
      shift
      ;;
    -h|--help)
      usage
      ;;
    -*|--*)
      echo "Unknown option $1"
      exit 1
      ;;
     *)
      ARGS+=("$1")
      shift
      ;;
  esac
done

if [ ! -z $CSV ] && [ -z $TABLE ]
then
  echo "Must specify --table-name <target-table> when loading from csv"
  exit 1
fi

eval $(avn service user-list --format \
  'DATABASE_PASSWORD={password} DATABASE_USER={username}' \
   $SERVICE)

SERVICE_URI=$(avn service get $SERVICE --format '{service_uri}')
DATABASE_HOST=$(echo $SERVICE_URI|cut -d: -f1)
DATABASE_PORT=$(echo $SERVICE_URI|cut -d: -f2)

eval $(echo $DOCKER_CMD \
  --rm clickhouse/clickhouse-client \
  --user $DATABASE_USER \
  --password $DATABASE_PASSWORD \
  --host $DATABASE_HOST \
  --port $DATABASE_PORT \
  --secure \
  $INSERT_QUERY)
~
~
