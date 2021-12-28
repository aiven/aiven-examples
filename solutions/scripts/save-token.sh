#! /bin/bash

avn user login
export AVN_TOKEN=$(cat ~/.config/aiven/aiven-credentials.json | jq -r .auth_token)