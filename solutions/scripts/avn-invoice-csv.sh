#!/bin/bash

usage() {
    printf "avn-invoice-csv generates all invoice to csv in a project.\nUsage: ./avn-invoice-csv.sh project_name\n" 1>&2;
    exit 1;
}

avnapi() {
export AVN_TOKEN=$(cat ~/.config/aiven/aiven-credentials.json | jq -r .auth_token)
curl -sH "Authorization: bearer $AVN_TOKEN" https://api.aiven.io/v1/$1
}

if [ "$#" -ne 1 ]; then
    usage;
fi

PROJECT=$1
BILLING_GROUP_ID=$(avnapi project/${PROJECT} | jq -r '.project.billing_group_id')

printf "Project [${PROJECT}]\nBilling Group ID: [${BILLING_GROUP_ID}]\n"
for INVOICE in $(avnapi billing-group/${BILLING_GROUP_ID}/invoice | jq -c '.invoices[] | { invoice_number: .invoice_number, download_cookie: .download_cookie }'); do
    INV_ID=$(echo ${INVOICE} | jq -r '.invoice_number')
    COOKIE=$(echo ${INVOICE} | jq -r '.download_cookie')

    avnapi billing-group/${BILLING_GROUP_ID}/invoice/${INV_ID}/csv?cookie=${COOKIE} > ${PROJECT}-${INV_ID}.csv
    if [ $? -eq 0 ]; then
        printf "Generated csv for invoice number: ${INV_ID}\n"
    fi
done
