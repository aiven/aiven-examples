#! /bin/bash
if [ $(avn user info --json | jq -r '.[].state') !=  "active" ]; then
    avn user login
fi

cat ~/.config/aiven/aiven-credentials.json