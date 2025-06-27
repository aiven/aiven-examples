# Overview
This repository provides a comprehensive migration accelerator designed to streamline the process of moving existing Kafka clusters to an Aiven Kafka environment. It offers a structured approach covering discovery, infrastructure provisioning, replication setup, monitoring, and validation. This accelerator utilizes external endpoint connections and multiple migration flows to migration topics in parallel.

--- 

# Table of Contents
1. Discovery
2. Infrastructure setup
3. Migration Replicaiton setup
4. Observability setup
5. Consumer validation

--------------------------------

## 1. Discovery
The discovery tool assists in generating a detailed report of your current source Kafka system. This initial step is crucial for understanding the existing cluster's configuration and data landscape before migration.

- Navigate to the discovery utility directory: /source-cluster-discovery-utility
- **For Aiven Source Clusters:** A `client.properties file` is required to specify connection information. Ensure you include `--command-config <client.properties path>` in the broker-specific commands.
- Update broker information, replacing <BOOTSTRAP-SERVER>:<PORT> with your source cluster's details.
- Execute the discovery script:
    ```bash 
    sh source-kafka-discovery.sh
    ```

-----------

## 2. Infrastructure Setup
This phase focuses on provisioning the necessary Aiven services: the destination Kafka cluster and the MirrorMaker 2 (MM2) service. It also establishes the required external endpoints for both the source and destination Kafka clusters.

The infrastructure setup will create:

- A destination Aiven Kafka service.
- An Aiven MirrorMaker 2 service.
- At least one external endpoint for the source Kafka cluster.
- At least one external endpoint for the new destination Kafka cluster.

**Note:** Each replication flow defined in the "Migration Replication Setup" step will necessitate its own dedicated external endpoint, allowing for scalable migration operations.

To provision the infrastructure using Terraform:

```bash
terraform init
terraform apply
```
Required Information for Infrastructure Setup:

- Aiven API Token
- Aiven Project Name
- Service Name Prefix (for new Aiven services)
- Destination Kafka Cloud Name
- MirrorMaker 2 Plan Name
- Source Kafka Cluster URI
- Destination Kafka Cluster Name


# 3. Migration Replication setup
Now that the services for the migration are spun up, the mirror maker service gets setup to replicate the source Kafka cluster information on the new Destination kafka cluster.


**Required Information for infrasture setup**
1. Aiven API Token
2. Aiven project name
3. source kafka service name
4. destination kafka service name
5. source kafka external endpoint id
6. destination kafka external endpoint id
7. MirrorMaker2 service name

* To get external endpoint Ids, you can run `avn service integration-endpoint-list --project <project name>` in the Aiven CLI
Multiple migration flows can be spun up to migrate groups of topics in parallel.



# 4. Observability Setup
Once the migration of data starts, spinning up the observability solution will allow service monitoring in the interem. 

1. navigate to `/mm2-migration-observability`
2. Update variable file 
2. run `terraform init`
3. run `terraform apply --var-file="<VAR FILE NAME>>`
4. Once services are spun up, navigate to the grafana dashboard to see migraiton metrics. 

# 5. Consumer Validation
Goal/Outcome : Offset sync tool inspects source and target cluster and compares the consumer group states. The tool emits the result as CSV.
more information found in the [ReadMe here](./mm2-offset-consumer-groups-validation/README.md). 
