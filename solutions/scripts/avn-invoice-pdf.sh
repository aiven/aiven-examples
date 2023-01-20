#!/bin/bash

usage() {
    printf "avn-invoice-pdf generates all invoice to csv in a project.\nUsage: ./avn-invoice-pdf.sh project_name\n" 1>&2;
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


for INVOICE in $(avnapi project/${PROJECT}/invoice | jq -c '.invoices[] | { invoice_number: .invoice_number, download_cookie: .download_cookie }'); do
    INV_ID=$(echo ${INVOICE} | jq -r '.invoice_number')
    COOKIE=$(echo ${INVOICE} | jq -r '.download_cookie')

    avnapi project/${PROJECT}/invoice/${INV_ID}/${COOKIE} > ${PROJECT}-${INV_ID}.pdf
    if [ $? -eq 0 ]; then
        printf "Generated pdf for invoice: ${INV_ID}\n"
    fi

done
