#!/bin/bash
set -e
source ./lab.env

lab_setup() {
cd terraform
terraform init
terraform plan
terraform apply \
&& printf "✅ " || echo "❌ "
echo "services created successfully."
cd ..

avn service user-creds-download ${SERVICE_KAFKA} --username avnadmin -d src/ \
&& printf "✅ " || echo "❌ "
echo "certificates and keys downloaded from ${SERVICE_KAFKA}"

echo
KAFKA_SERVICE_URI=$(avn service list --json ${SERVICE_KAFKA} | jq -r '.[].service_uri')
echo ${KAFKA_SERVICE_URI}
cat src/config.py.example > src/config.py
sed -i '' -e "s/address:port/${KAFKA_SERVICE_URI}/" src/config.py \
&& printf "✅ " || echo "❌ "
echo "src/config.py setup completed"

python3 -m venv venv \
&& printf "✅ " || echo "❌ "
echo "python venv environment setup completed"

. venv/bin/activate
cd src
pip install -r requirements.txt \
&& printf "✅ " || echo "❌ "
echo "python requirements installed successfully"
deactivate
cd ..
}

lab_teardown() {
rm -f src/ca.pem src/service.cert src/service.key
cd terraform
terraform destroy \
&& printf "✅ " || echo "❌ "
echo "services deleted successfully."
cd ..

}

lab_producer() {
. venv/bin/activate
cd src && python3 producer.py
deactivate
}

lab_consumer() {
. venv/bin/activate
cd src && python3 consumer.py
deactivate
}

case $1 in
    setup)
        lab_setup ;;
    teardown)
        lab_teardown ;;
    consumer)
        lab_consumer ;;
    producer)
        lab_producer ;;
    *)
        printf "Usage: ./lab.sh [ setup | producer | consumer | teardown ]\n" ;;
esac
