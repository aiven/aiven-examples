resource "aiven_flink" "flink" {
  project      = var.aiven_project
  cloud_name   = var.cloud_name
  plan         = var.flink_plan
  service_name = "securitylab-flink"
}

resource "aiven_kafka" "kafka" {
  project      = var.aiven_project
  cloud_name   = var.cloud_name
  plan         = var.kafka_plan
  service_name = "securitylab-kafka"
  kafka_user_config {
    kafka_rest      = "true"
  }
}

resource "aiven_opensearch" "opensearch" {
  project      = var.aiven_project
  cloud_name   = var.cloud_name
  plan         = var.opensearch_plan
  service_name = "securitylab-os"
}

resource "aiven_pg" "pg" {
  project      = var.aiven_project
  cloud_name   = var.cloud_name
  plan         = var.postgres_plan
  service_name = "securitylab-pg"
}

resource "aiven_service_integration" "flink_to_kafka" {
  project                  = var.aiven_project
  integration_type         = "flink"
  destination_service_name = aiven_flink.flink.service_name
  source_service_name      = aiven_kafka.kafka.service_name
}

resource "aiven_service_integration" "flink_to_os" {
  project                  = var.aiven_project
  integration_type         = "flink"
  destination_service_name = aiven_flink.flink.service_name
  source_service_name      = aiven_opensearch.opensearch.service_name
}

resource "aiven_service_integration" "flink_to_pg" {
  project                  = var.aiven_project
  integration_type         = "flink"
  destination_service_name = aiven_flink.flink.service_name
  source_service_name      = aiven_pg.pg.service_name
}

resource "aiven_kafka_topic" "source" {
  project      = aiven_kafka.kafka.project
  service_name = aiven_kafka.kafka.service_name
  partitions   = 2
  replication  = 3
  topic_name   = "security_logs"
}

resource "aiven_flink_application" "pg-audit-logs" {
  project      = var.aiven_project
  service_name = aiven_flink.flink.service_name
  name         = "pg-audit-logs"
}

resource "aiven_flink_application_version" "pg-audit-logs-version" {
  project      = aiven_flink.flink.project
  service_name = aiven_flink.flink.service_name
  application_id = aiven_flink_application.pg-audit-logs.application_id
  statement = <<EOT
    INSERT INTO pg_sink
    SELECT
        user_id,
        COUNT(*) AS login_attempts,
        COUNT(DISTINCT source_ip) AS distinct_ips,
        CAST(MAX(ts_ltz) AS VARCHAR) AS time_since_last_login
    FROM kafka_source
    WHERE action = 'login'
    GROUP BY
        user_id,
        TUMBLE(ts_ltz, INTERVAL '30' SECONDS);
  EOT
  sink {
    create_table   = <<EOT
    CREATE TABLE pg_sink (
        user_id INT PRIMARY KEY,
        login_attempts BIGINT NOT NULL,
        distinct_ips BIGINT NOT NULL,
        time_since_last_login STRING
    ) WITH (
        'connector' = 'jdbc',
        'url' = 'jdbc:postgresql://',
        'table-name' = 'audit_logs'
    );
    EOT
    integration_id = aiven_service_integration.flink_to_pg.integration_id
  }
  source {
    create_table   = <<EOT
    CREATE TABLE kafka_source (
        time_stamp BIGINT,
        user_id INT,
        action STRING,
        source_ip STRING,
        ts_ltz AS NOW(),
        WATERMARK FOR ts_ltz AS ts_ltz
    ) WITH (
        'connector' = 'kafka',
        'properties.bootstrap.servers' = '',
        'scan.startup.mode' = 'earliest-offset',
        'topic' = 'security_logs',
        'value.format' = 'json'
    )
    EOT
    integration_id = aiven_service_integration.flink_to_kafka.integration_id
  }
}

resource "aiven_flink_application" "os-suspecious-logins" {
  project      = var.aiven_project
  service_name = aiven_flink.flink.service_name
  name         = "os-suspecious-logins"
}

resource "aiven_flink_application_version" "os-suspecious-logins-v1" {
  project      = aiven_flink.flink.project
  service_name = aiven_flink.flink.service_name
  application_id = aiven_flink_application.os-suspecious-logins.application_id
  statement = <<EOT
    INSERT INTO os_sink
    SELECT k.ts_ltz AS time_stamp, k.user_id, k.action, k.source_ip
    FROM kafka_source k
    JOIN pg_source p ON k.user_id = p.user_id
    WHERE k.action = 'login';
  EOT
  sink {
    create_table   = <<EOT
      CREATE TABLE os_sink (
          time_stamp TIMESTAMP,
          user_id INT,
          action STRING,
          source_ip STRING  
      ) WITH (
          'connector' = 'elasticsearch-7',
          'hosts' = '',
          'index' = 'suspecious-logins'
      )
    EOT
    integration_id = aiven_service_integration.flink_to_os.integration_id
  }
  source {
    create_table   = <<EOT
      CREATE TABLE kafka_source (
          time_stamp BIGINT,
          user_id INT,
          action STRING,
          source_ip STRING,
          ts_ltz AS NOW(),
          WATERMARK FOR ts_ltz AS ts_ltz
      ) WITH (
          'connector' = 'kafka',
          'properties.bootstrap.servers' = '',
          'scan.startup.mode' = 'earliest-offset',
          'topic' = 'security_logs',
          'value.format' = 'json'
      )
    EOT
    integration_id = aiven_service_integration.flink_to_kafka.integration_id
  }
  source {
    create_table   = <<EOT
      CREATE TABLE pg_source (
          user_id INT PRIMARY KEY,
          login_attempts BIGINT NOT NULL,
          distinct_ips BIGINT NOT NULL,
          time_since_last_login STRING
      ) WITH (
          'connector' = 'jdbc',
          'url' = 'jdbc:postgresql://',
          'table-name' = 'audit_logs'
      );    
    EOT
    integration_id = aiven_service_integration.flink_to_pg.integration_id
  }  
}
