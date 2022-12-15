#!/bin/sh

AVN_SERVICE=$1
AVN_SERVICE_URI=$(avn service list --json ${AVN_SERVICE} | jq -r '.[].service_uri')
AVN_SCHEMA_URI="https://$(avn service list --json ${AVN_SERVICE} | jq -r '.[].connection_info.schema_registry_uri' | cut -d'@' -f2)"
AVN_PASSWORD=$(avn service user-get --username avnadmin --json  ${AVN_SERVICE} | jq -r '.password')

echo "bootstrap.servers=${AVN_SERVICE_URI}" > kafka.properties
echo "security.protocol=SSL" >> kafka.properties
echo "ssl.truststore.location=${PWD}/client.truststore.jks" >> kafka.properties
echo "ssl.truststore.password=changeit" >> kafka.properties
echo "ssl.keystore.type=PKCS12" >> kafka.properties
echo "ssl.keystore.location=${PWD}/client.keystore.p12" >> kafka.properties
echo "ssl.keystore.password=changeit" >> kafka.properties
echo "ssl.key.password=changeit" >> kafka.properties

echo "schema.registry.url=${AVN_SCHEMA_URI}" > schema.properties
echo "basic.auth.credentials.source=USER_INFO" >> schema.properties
echo "basic.auth.user.info=avnadmin:${AVN_PASSWORD}" >> schema.properties
