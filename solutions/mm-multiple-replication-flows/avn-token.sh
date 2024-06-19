#! /bin/bash
if [ $(avn user info --json | jq -r '.[].state') !=  "active" ]; then
    avn user login
fi

cat $AIVEN_CREDENTIALS_FILE
