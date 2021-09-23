#!/bin/bash

usage() { printf "\nList all services with public access.\nUsage: TOKEN=<token> $0 [project=<project_name>]\n" 1>&2; exit 1; }

for ARGUMENT in "$@"
do
    KEY=$(echo $ARGUMENT | cut -f1 -d=)
    VALUE=$(echo $ARGUMENT | cut -f2 -d=)

    case "$KEY" in
            project) PROJECTS=$VALUE ;;

      help)
            usage;
            exit $?;;

            *)
            usage;
            exit $?;;
    esac
done

if [[ -z "$TOKEN" ]]; then
    usage
fi

if [[ -z "$PROJECTS" ]]; then
    # get all projects
    PROJECTS=$(curl -sX GET -H "Authorization: Bearer $TOKEN" "https://api.aiven.io/v1/project" | jq -r '.projects | .[] .project_name')
    sleep 1s
fi

for PROJECT in $PROJECTS; do
    SERVICES_JSON=$(curl -sX GET -H "Authorization: Bearer $TOKEN" "https://api.aiven.io/v1/project/$PROJECT/service")
    sleep 1s
    # find all VPC services then look for ones that have public routes
    VPC_PUBLIC=$(echo $SERVICES_JSON | jq '[.services | .[] | select(.project_vpc_id != null )]' | jq -r 'map(select( any(.components[]; .route == "public" ))) | .[] | .service_name')
    for SERVICE in $VPC_PUBLIC; do
        echo "$PROJECT $SERVICE VPC_WITH_PUBLIC_ROUTE"
    done
    # find all non VPC services
    NON_VPC_PUBLIC=$(echo $SERVICES_JSON | jq -r '.services | .[] | select(.project_vpc_id == null ) | .service_name')
    for SERVICE in $NON_VPC_PUBLIC; do
        echo "$PROJECT $SERVICE NON_VPC"
    done
done
