#!/bin/bash
kubectl create secret generic m3-prom \
--from-file=M3_URL=../../k8s/secrets/aiven/m3_prom_uri \
--from-file=M3_USER=../../k8s/secrets/aiven/m3_prom_user \
--from-file=M3_PASSWORD=../../k8s/secrets/aiven/m3_prom_pwd \
-n monitoring
