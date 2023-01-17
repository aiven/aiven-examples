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


for INVOICE in $(avnapi project/felixwu-demo/invoice | jq -c '.invoices[] | { billing_group_id: .billing_group_id, invoice_number: .invoice_number }'); do
    BG_ID=$(echo ${INVOICE} | jq -r '.billing_group_id')
    INV_ID=$(echo ${INVOICE} | jq -r '.invoice_number')
    avnapi billing-group/${BG_ID}/invoice/${INV_ID}
    printf "\n"
done

