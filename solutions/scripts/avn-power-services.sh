#!/bin/bash

# jq needs to be installed https://stedolan.github.io/jq/
# The PROJECT services needs to have at least these 2 tags
#        { "env": ENVIRONMENT,
#    "start-seq": SEQUENCE_NUMBER }
#      ENVIRONMENT could be anything like "test1", "PROD", "dev", etc
#  SEQUENCE_NUMBER should be an integer like 10, 50, 130, etc
# avn cli needs to be authenticated
#  https://console.aiven.io/profile/auth "Authentication tokens" -> [Generate token]
#  avn user login --token [email]
#
# This file follows these bash/sh shell scripts rules https://github.com/koalaman/shellcheck

USAGE="usage: --project PROJECT --tag-env ENVIRONMENT [--on | --off]"
if [ $# -ne 5 ]
then
  echo "$USAGE"
  exit 1
fi

while [ $# -gt 0 ]; do
  case $1 in
    --project)
      shift && PROJECT="$1"
      ;;
    --tag-env)
      shift && TAG_ENV="$1"
      ;;
    --on)
      shift && POWER="ON"
      ;;
    --off)
      shift && POWER="OFF"
      ;;
    *)
      echo "unknown argument $1"
      exit 1
      ;;
  esac
  shift
done 

echo "Turning [$POWER] services for project [$PROJECT] tagged [$TAG_ENV]"

function service_list() {
  local services
  services=$(avn service list --project "$PROJECT" --json | jq -c '[.[] | {service_name, state, tags }]')
  echo "$services"
}

function service_update_power() {
  local service_name=$1
  local power_arg
  if [ "$POWER" == "ON" ]; then
    power_arg="--power-on"
  else
    power_arg="--power-off"
  fi
  avn service update --project "$PROJECT" "$power_arg" "$service_name"
}

function filter_services() {
  local services=$1
  local filtered
  filtered=$(jq -c --arg env "$TAG_ENV" '[.[] | select(.tags.env == $env)]' <<< "$services")
  echo "$filtered"
}

function sort_services() {
  local services=$1
  local sorted
  if [ "$POWER" == "ON" ]; then
    sorted=$(jq -c 'sort_by(.tags."start-seq")' <<< "$services")
  else
    sorted=$(jq -c 'sort_by(.tags."start-seq") | reverse' <<< "$services")
  fi
  echo "$sorted"
}

function power() {
  local services=$1
  local service_name
  local state
  jq -c '.[]' <<< "$services" | while read -r service; do
    service_name=$(jq -r '.service_name' <<< "$service")
    state=$(jq -r '.state' <<< "$service")
    if { [ "$state" == "POWEROFF" ] && [ "$POWER" == "ON" ]; } ||
       { [ "$state" == "RUNNING" ]  && [ "$POWER" == "OFF" ]; } then
      echo "Powering $POWER $service_name ..."
      service_update_power "$service_name"
    else
      echo "$service_name is [$state]"
    fi
  done
}

services=$(service_list)
filtered=$(filter_services "$services")
sorted=$(sort_services "$filtered")
power "$sorted"