function projectServices() {
  curl -s --request GET \
  --url "https://api.aiven.io/v1/project/${1}/service" \
  --header "Authorization: Bearer ${AIVEN_API_TOKEN}" \
  --header 'content-type: application/json' \
}

# Generate Import Statements
function tfImports() {
  projectServices ${1} | \
  jq -r --arg PROJECT ${1} '.services[]|"import {\n to = aiven_"+ .service_type + "." + .service_name + "\n id = \"" + $PROJECT + "/" + .service_name + "\"\n}"'
}

# Wrapper function :
function tfImport() {
  # Beta for Thanos, Dragonfly... 
  export PROVIDER_AIVEN_ENABLE_BETA=1

  tfImports "${1}" > "${1}".imports.tf
  terraform init
  terraform plan -generate-config-out="${1}".tf
}

# Clear existing state / imports:
function tfClear() {
  terraform state list | xargs terraform state rm
}