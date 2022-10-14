#!/bin/bash

usage() {
    printf "avn-mysqldump create a fork of mysql to take a mysqldump then terminates the fork.\nUsage: ./avn-fork-mysqldump.sh mysqlservice hostname port username password aiven_project mysql_fork_name\n" 1>&2;
    exit 1;
}

if [ "$#" -ne 7 ]; then
    usage;
fi

AVN_SERVICE=$1
AVN_HOST=$2
AVN_PORT=$3
AVN_USER=$4
AVN_PASS=$5
AVN_PROJECT=$6
AVN_SERVICE_PLAN=startup-4
AVN_MYSQL_FORK_NAME=$7

avn service create $AVN_MYSQL_FORK_NAME -t mysql --plan $AVN_SERVICE_PLAN --project $AVN_PROJECT -c service_to_fork_from=$AVN_SERVICE

if [ "$?" -ne 0 ]; then
    printf "ERROR: failed to create a fork ${AVN_MYSQL_FORK_NAME} from service ${AVN_SERVICE}\n" 1>&2;
    exit 1;
fi
avn service wait $AVN_MYSQL_FORK_NAME
sleep 60

# do not backup default system databases - mysql, performance_schema, information_schema, sys
AVN_DBS=$(echo "show databases" | mysql --host=$AVN_HOST --port=$AVN_PORT -u $AVN_USER --password=$AVN_PASS | grep -Ev "^(Database|mysql|performance_schema|information_schema|sys)$")

AVN_BACKUP=$AVN_MYSQL_FORK_NAME-backup-$(date +'%Y%m%d%H%M%S').gz
echo "Backup databases: ["$AVN_DBS"]" to $AVN_BACKUP

## Compressed version
mysqldump --host=$AVN_HOST --port=$AVN_PORT -u $4 -p --password=$5 -B $AVN_DBS | gzip -9 > $AVN_BACKUP

echo $AVN_AVN_MYSQL_FORK_NAME | avn service terminate --project $AVN_PROJECT -f $AVN_MYSQL_FORK_NAME
