#!/bin/bash

usage() {
    printf "avn-vpc-datasource generates vpc-data-source.tf in a project.\nUsage: ./avn-vpc-datasource.sh project_name\n" 1>&2;
    exit 1;
}

if [ "$#" -ne 1 ]; then
    usage;
fi

for VPC_JSON in $(avn vpc list --project $1 --json | jq -c '.[]');
do
    VPC_ID=$(echo $VPC_JSON | jq -r '.project_vpc_id')
    VPC_CIDR="cidr_$(echo $VPC_JSON | jq -r '.network_cidr' | sed -E 's/\.|\//\-/g')"

    printf "data \"aiven_project_vpc\" \"${VPC_CIDR}\" {\n" >> vpc-data-source.tf
    printf "  vpc_id = \"$1/${VPC_ID}\"\n}\n" >> vpc-data-source.tf
done
cat vpc-data-source.tf
