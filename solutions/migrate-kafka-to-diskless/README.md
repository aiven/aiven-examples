# Kafka to Diskless Storage Migration Accelerator

This repository provides a comprehensive migration accelerator designed to streamline the process of migrating existing Kafka topics to Aiven Kafka with diskless topics enabled. It offers a structured approach covering discovery, infrastructure provisioning, replication setup, monitoring, and validation. This accelerator utilizes external endpoint connections and MirrorMaker 2 (MM2) to migrate topics to diskless storage in parallel.

## Overview

Diskless storage is Aiven's solution for high-throughput, cost-effective Kafka storage that writes directly to Object Storage. This migration accelerator helps you:

- Discover your existing Kafka cluster configuration
- Provision a destination Kafka service with diskless storage enabled
- Set up MirrorMaker 2 for seamless data replication
- Monitor migration progress with observability dashboards
- Validate consumer group offset synchronization

**Key Features:**
- Automated infrastructure provisioning with Terraform
- Support for parallel migration flows
- Pre-configured diskless topics with optimal settings
- Comprehensive monitoring and validation tools
- Consumer group offset synchronization validation

---

## Table of Contents

1. [Discovery](#1-discovery)
2. [Infrastructure Setup](#2-infrastructure-setup)
3. [Migration Replication Setup](#3-migration-replication-setup)
4. [Observability Setup](#4-observability-setup)
5. [Consumer Validation](#5-consumer-validation)

---

## 1. Discovery

The discovery tool assists in generating a detailed report of your current source Kafka system. This initial step is crucial for understanding the existing cluster's configuration and data landscape before migration. Resulting files identify consumer groups and topics that are active.

### Steps

1. Navigate to the discovery utility directory:
   ```bash
   cd source-cluster-discovery-utility
   ```

2. **For Aiven Source Clusters:** A `client.properties` file is required to specify connection information. Ensure you include `--command-config <client.properties path>` in the broker-specific commands.

3. Update broker information in `source-kafka-discovery.sh`, replacing `<BOOTSTRAP-SERVER>:<PORT>` with your source cluster's details.

4. Execute the discovery script:
   ```bash
   sh source-kafka-discovery.sh
   ```

The script will generate reports including:
- Consumer groups and their states
- Topic configurations
- Broker configurations
- System metadata

### Output Files

- `consumer_groups_source.txt` - All consumer groups from the cluster
- `consumer_groups_state_source.txt` - Consumer group states
- `topics_list_source.txt` - All topic details
- `kafka_broker_configs.txt` - Broker configurations

---

## 2. Infrastructure Setup

This phase focuses on provisioning the necessary Aiven services: the destination Kafka cluster with diskless storage enabled and the MirrorMaker 2 (MM2) service. It also establishes the required external endpoints for the source Kafka cluster. The endpoint abstracts the source Kafka connection and facilitates the setup for migration if multiple replication streams are being used in parallel.

### What Gets Created

- **A destination Aiven Kafka service** with:
  - Diskless storage enabled
  - Tiered storage enabled
  - Kafka REST API enabled
  - Optimized configuration for diskless topics
- **An Aiven MirrorMaker 2 service** configured for high-throughput replication
- **External endpoint(s)** for the source Kafka cluster
- **Diskless topics** pre-created based on your topic list

**Note:** Each replication flow defined in the "Migration Replication Setup" step will necessitate its own dedicated external endpoint, allowing for scalable migration operations.

### Prerequisites

Before running the infrastructure setup, you need to:

1. **Identify topics for diskless migration**: Create a file listing the topics you want to migrate to diskless storage. The default file is `diskless_topics_names.txt` in the `infra-integration-setup` directory.

   Example `diskless_topics_names.txt`:
   ```
   logging-topic
   metrics-topic
   product-topic
   mock-motorcycle-data
   ```

2. **Prepare your variables file**: Create a `terraform.tfvars` file based on `variables-example.tfvars.examples`:

   ```hcl
   aiven_api_token = "your-api-token-here"
   aiven_project_name = "your-aiven-project-name"
   service_prefix = "migration-"
   cloud_name_primary = "google-europe-west1"
   mm2_plan_cluster_2 = "business-8"
   aiven_source_bootstrap_url = "source-kafka.example.com:9092"
   kafka_source_name = "source-kafka-service"
   dest_kafka_plan = "business-16-inkless"
   diskless_topics_file = "./diskless_topics_names.txt"
   ```

### Required Information

- Aiven API Token
- Aiven Project Name
- Service Name Prefix (for new Aiven services)
- Destination Kafka Cloud Name
- MirrorMaker 2 Plan Name
- Source Kafka Cluster Bootstrap URL
- Destination Kafka Plan (must support diskless storage, e.g., `business-16-inkless`)
- Path to diskless topics file

### Deployment Steps

1. Navigate to the infrastructure setup directory:
   ```bash
   cd infra-integration-setup
   ```

2. Initialize Terraform:
   ```bash
   terraform init
   ```

3. Review the execution plan:
   ```bash
   terraform plan -var-file="terraform.tfvars"
   ```

4. Apply the configuration:
   ```bash
   terraform apply -var-file="terraform.tfvars"
   ```

### Diskless Topic Configuration

Topics created during infrastructure setup are configured with:
- **Replication Factor**: 1 (diskless topics write directly to Object Storage for durability)
- **Partitions**: 3 (configurable per topic)
- **Diskless Storage**: Enabled
- **Topic names**: Read from `diskless_topics_names.txt`

**Important:** Diskless topics always use replication factor 1 because they achieve durability through Object Storage, not through Kafka replication.

### Outputs

After applying the Terraform configuration, you'll get:
- Destination Kafka service name
- MirrorMaker 2 service name
- External endpoint IDs (needed for replication setup)
- Service connection URIs

To view outputs:
```bash
terraform output
```

To get external endpoint IDs:
```bash
avn service integration-endpoint-list --project <project-name>
```

---

## 3. Migration Replication Setup

Now that the services for the migration are spun up, the MirrorMaker service gets configured to replicate data from the source Kafka cluster to the new destination Kafka cluster with diskless storage.

### Prerequisites

You'll need the following information from the infrastructure setup:

1. Aiven API Token
2. Aiven Project Name
3. Source Kafka Service Name
4. Destination Kafka Service Name
5. Source Kafka External Endpoint ID
6. Destination Kafka External Endpoint ID (if using external endpoint for destination)
7. MirrorMaker 2 Service Name

**To get external endpoint IDs:**
```bash
avn service integration-endpoint-list --project <project-name>
```

### Multiple Replication Flows

Multiple migration flows can be spun up to migrate groups of topics in parallel. Each flow requires:
- Its own external endpoint (for source)
- Its own MirrorMaker 2 service integration
- Its own replication flow configuration

### Deployment Steps

1. Navigate to the migration replication setup directory:
   ```bash
   cd migration-replication-setup
   ```

2. Create a `terraform.tfvars` file based on `example-variables.tfvars.examples`:

   ```hcl
   aiven_project_name = "your-project-name"
   aiven-labs-mm2-rf3-set1 = "migration-mm2-rf3-set1"
   destination_kafka_service = "migration-dest-kafka-1"
   external_source_aiven_kafka_endpoint_id_rf3_set1 = "endpoint-id-from-infra-setup"
   ```

3. Initialize and apply:
   ```bash
   terraform init
   terraform plan -var-file="terraform.tfvars"
   terraform apply -var-file="terraform.tfvars"
   ```

### Replication Flow Configuration

The replication flow is configured with:
- **Replication Policy**: Identity (preserves topic names)
- **Offset Synchronization**: Enabled
- **Heartbeats**: Enabled
- **Topic Filtering**: Uses regex patterns from the diskless topics list
- **Blacklist**: Excludes internal topics, replicas, and system topics

**Note:** The replication flow is initially created with `enable = false` in the infrastructure setup. You can enable it in the migration replication setup or manually via the Aiven console/API.

---

## 4. Observability Setup

Once the migration of data starts, spinning up the observability solution will allow service monitoring during the migration process.

### Deployment Steps

1. Navigate to the observability directory:
   ```bash
   cd mm2-migration-observability
   ```

2. Create a `terraform.tfvars` file with your project details:
   ```hcl
   aiven_project_name = "your-project-name"
   mm2_service_name = "migration-mm2-rf3-set1"
   # ... other required variables
   ```

3. Initialize and apply:
   ```bash
   terraform init
   terraform plan -var-file="terraform.tfvars"
   terraform apply -var-file="terraform.tfvars"
   ```

4. Once services are spun up, navigate to the Grafana dashboard to see migration metrics.

### Available Dashboards

The observability setup includes pre-configured Grafana dashboards:
- **MM2 Migration Dashboard**: Monitor replication lag, throughput, and error rates
- **MM2 Observability Dashboard**: Detailed metrics on MirrorMaker 2 performance

Key metrics to monitor:
- Replication lag per topic
- Messages per second (throughput)
- Consumer group offset sync status
- Error rates and failed tasks
- Network and resource utilization

---

## 5. Consumer Validation

The Offset Synchronization tool inspects the source and target clusters and compares the consumer group states. The tool emits the results to confirm the offsets have been successfully synced between clusters.

### Overview

This validation step ensures that:
- Consumer group offsets are properly synchronized
- All active consumer groups are accounted for
- Offset translation between source and target is accurate

### Detailed Information

For comprehensive information on using the offset validation tool, see the [README in the validation directory](./mm2-offset-consumer-groups-validation/README.md).

### Quick Start

1. Navigate to the validation directory:
   ```bash
   cd mm2-offset-consumer-groups-validation
   ```

2. Prepare the MM2 configuration file based on `example-mm2-temp1.properties`

3. Run the validation tool:
   ```bash
   ./bin/kafka-mirrormaker-offset-sync-inspector.sh \
     --mm2-config <config-file-path> \
     --admin-timeout PT10M \
     --request-timeout PT60S \
     --output-path validation-results.csv
   ```

4. Review the CSV output to identify any consumer groups that require attention.

---

## Best Practices

### Diskless Storage Considerations

1. **Topic Selection**: Not all topics are suitable for diskless storage. Consider:
   - High-throughput, high-latency workloads
   - Topics with large message sizes
   - Topics where cost optimization is important

2. **Client Configuration**: Configure your Kafka clients for optimal performance:
   - Use AZ-aware client IDs: `client.id="<custom_id>,diskless_az=<rack>"`
   - Increase batch sizes for producers
   - Tune fetch sizes for consumers
   - See `diskless-foundation-setup/kafka_client_settings.ini` for examples

3. **Replication Factor**: Remember that diskless topics use replication factor 1. Durability is achieved through Object Storage, not Kafka replication.

### Migration Strategy

1. **Phased Migration**: Start with non-critical topics to validate the process
2. **Parallel Flows**: Use multiple replication flows for different topic groups
3. **Monitoring**: Keep observability dashboards active throughout migration
4. **Validation**: Regularly run offset validation to ensure data consistency
5. **Testing**: Test consumer applications against the destination cluster before cutover

### Performance Tuning

- Adjust `tasks_max_per_cpu` in MM2 configuration based on workload
- Tune producer batch sizes and linger time for high-throughput topics
- Monitor replication lag and adjust consumer max poll records if needed
- Consider topic partitioning strategy for optimal parallelism

---

## Cleanup

To destroy all resources created by this migration accelerator:

1. **Destroy replication flows** (migration-replication-setup):
   ```bash
   cd migration-replication-setup
   terraform destroy -var-file="terraform.tfvars"
   ```

2. **Destroy observability** (if needed):
   ```bash
   cd mm2-migration-observability
   terraform destroy -var-file="terraform.tfvars"
   ```

3. **Destroy infrastructure** (this will remove all services):
   ```bash
   cd infra-integration-setup
   terraform destroy -var-file="terraform.tfvars"
   ```

**Warning:** Destroying the infrastructure will delete the destination Kafka service and all data. Ensure you have completed the migration and cutover before destroying resources.

---

## Troubleshooting

### Common Issues

1. **Replication Flow Not Starting**
   - Verify external endpoints are correctly configured
   - Check that source cluster is accessible
   - Ensure MM2 service integrations are properly created

2. **High Replication Lag**
   - Review MM2 task configuration
   - Check network connectivity between clusters
   - Consider increasing MM2 plan size
   - Verify producer batch sizes are optimized

3. **Offset Sync Issues**
   - Run the validation tool to identify specific problems
   - Check that `sync_group_offsets_enabled` is true
   - Verify consumer groups are active on source cluster

4. **Diskless Topic Creation Fails**
   - Ensure Kafka plan supports diskless storage
   - Verify topic names in `diskless_topics_names.txt` are valid
   - Check that tiered storage is enabled

### Getting Help

- Review Aiven documentation: [Kafka Diskless Storage](https://docs.aiven.io/docs/products/kafka/concepts/diskless-storage)
- Check MirrorMaker 2 logs in Aiven console
- Review Grafana dashboards for detailed metrics
- Consult the validation tool output for offset sync issues

---

## Additional Resources

- [Aiven Kafka Documentation](https://docs.aiven.io/docs/products/kafka)
- [Aiven Terraform Provider Documentation](https://registry.terraform.io/providers/aiven/aiven/latest/docs)
- [Kafka Diskless Storage Best Practices](https://docs.aiven.io/docs/products/kafka/concepts/diskless-storage)
- [MirrorMaker 2 Documentation](https://docs.aiven.io/docs/products/kafka/howto/mirrormaker-2)
- [Diskless Foundation Setup](../diskless-foundation-setup/README.md) - For setting up new diskless topics from scratch

---

## Notes

- Diskless storage is optimized for high-throughput, high-latency workloads
- Ensure your clients are configured with AZ awareness for optimal performance
- For classic topics, the default replication factor is set to 3 for high availability
- For diskless topics, the replication factor is always 1 because durability is achieved through Object Storage
- Tiered storage is enabled to efficiently manage data lifecycle
- The migration process preserves topic names and consumer group offsets
- Multiple replication flows can run in parallel for faster migration of large topic sets
