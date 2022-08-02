# Application stack example

This repo provides an example of deploying a repeatable customer stack (other terms may be pod, group etc). 

The "stack" consists of several Aiven services, Kafka, Opensearch, M3DB and Grafana. The services are deployed within a customers VPC on GCP. 

Metrics and logging services are integrated, as well as Prometheus endpoint to allow the customer point existing scraping tools against the Aiven services. 

## Setup

1. Create a terraform.tfvars file in the root directory of this project. Add the following to it, filling in the correct values for your project

```
aiven_api_token = "MY_AIVEN_API_TOKEN"
account = "My Aiven Account"
project = "aiven-project-name"
external_account_id = "my-gpc-project-id"
external_vpc_id = "gcp-vpc-id"
vpc_cidr_range = "10.1.0.0/24"
prom_username       = "promuser"
prom_password       = "my-secret-password-ssshhh"
```

2. In the root `variables.tf` file, update the default values to your preferred values. e.g. change the plan sizes, default cloud etc. Note these can also be provided to terraform itself.

3. Initialze terraform

```
terraform init
```

4. Provided step (3) is successful, plan and apply your services 

```
terraform plan
# provided above command looks ok
terraform apply
```