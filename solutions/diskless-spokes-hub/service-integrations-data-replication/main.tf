# // DATA REPLICATION : MM2 spoke service integration for Data Replication
resource "aiven_service_integration" "mm2-spoke-svc-integration-data-source-1" {
project                  = var.aiven_project_name
integration_type         = "kafka_mirrormaker"
source_service_name      = aiven_kafka.spoke_kafka_1.service_name
destination_service_name = aiven_kafka_mirrormaker.mm2_data_replication_spoke_1.service_name
kafka_mirrormaker_user_config {
    cluster_alias = "aiven-spoke-data-source-cluster-1" //could use name suffix with region name 
    kafka_mirrormaker {
        producer_max_request_size = 66901452 // default
        producer_buffer_memory = 33554432 // default, required size is that producer batch fits to buffer memory.
        producer_batch_size = 12000 
        producer_linger_ms = 100
    }
    }
}

# // DATA REPLICATION : MM2 Hub service integration for Data Replication
resource "aiven_service_integration" "mm2-hub-svc-integration-data-destination" {
project                  = var.aiven_project_name
integration_type         = "kafka_mirrormaker"
source_endpoint_id       = var.external_source_aiven_kafka_endpoint_id_euw1
destination_service_name = aiven_kafka_mirrormaker.mm2_data_replication_spoke_1.service_name
kafka_mirrormaker_user_config {
    cluster_alias = "aiven-hub-data-destination-cluster" // could suffix with region name
    kafka_mirrormaker {
        producer_max_request_size = 66901452 // default
        producer_buffer_memory = 33554432 // default, required size is that producer batch fits to buffer memory.
        producer_batch_size = 12000
        producer_linger_ms = 100
    }
    }
}

