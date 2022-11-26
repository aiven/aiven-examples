#!/bin/bash

usage() {
    printf "avn-vpc-import imports vpc in a project to terraform state.\nUsage: ./avn-vpc-import.sh project_name\n" 1>&2;
    exit 1;
}

if [ "$#" -ne 1 ]; then
    usage;
fi

i=0
for vpc in $(avn vpc list --project $1 --json | jq -r '.[].project_vpc_id');
do
  terraform import aiven_project_vpc.vpc$i $1/$vpc
  i=$((i+1))
done
