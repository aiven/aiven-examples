resource "aiven_mysql" "primary_mysql" {
  project = var.aiven_project_name
  cloud_name = var.cloud_name_primary
  plan = var.mysql_plan
  service_name = "${var.service_prefix}-primary-mysql"
  maintenance_window_dow = "monday"
  maintenance_window_time = "10:00:00"

  mysql_user_config {
    mysql_version = var.mysql_version
    additional_backup_regions = ["google-us-central1"]
    binlog_retention_period = 1200
    mysql {
      connect_timeout = 3
      sql_mode = "ANSI,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION,NO_ZERO_DATE,NO_ZERO_IN_DATE"
      sql_require_primary_key = true
      tmp_table_size = 16777216 
      wait_timeout = 57600
      max_allowed_packet = 16777216
      slow_query_log = true
      log_output = "INSIGHTS,TABLE"
      interactive_timeout = 3600
      innodb_write_io_threads = 4
      innodb_rollback_on_timeout = true
      innodb_read_io_threads = 8
      innodb_lock_wait_timeout = 60
      innodb_flush_neighbors = 1
      information_schema_stats_expiry = 86400
    }

    public_access {
      mysql = true
      prometheus = true
    }
  }
  
  timeouts {
    create = "20m"
    update = "15m"
  }
}

resource "aiven_mysql" "dr_mysql" {
  project = var.aiven_project_name
  cloud_name = var.cloud_name_dr
  plan = var.mysql_dr_plan
  service_name = "${var.service_prefix}-dr-mysql"
  maintenance_window_dow = "monday"
  maintenance_window_time = "10:00:00"

  /*service_integrations {
    integration_type = "read_replica"
    source_service_name = "slabs-demo-primary-mysql"
  }*/
  mysql_user_config {
    mysql_version = var.mysql_version
    
    mysql {
      connect_timeout = 3
      sql_mode = "ANSI,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION,NO_ZERO_DATE,NO_ZERO_IN_DATE"
      sql_require_primary_key = true
      tmp_table_size = 16777216 
      wait_timeout = 57600
      max_allowed_packet = 16777216
      slow_query_log = true
      log_output = "INSIGHTS,TABLE"
      interactive_timeout = 3600
      innodb_write_io_threads = 4
      innodb_rollback_on_timeout = true
      innodb_read_io_threads = 8
      innodb_lock_wait_timeout = 60
      innodb_flush_neighbors = 1
      information_schema_stats_expiry = 86400
    }

    public_access {
      mysql = true
      prometheus = true
    }
  }
  timeouts {
    create = "20m"
    update = "15m"
  }
}

resource "time_sleep" "wait_mysql_primary_readiness" {
  depends_on = [
    aiven_mysql.primary_mysql
  ]
  create_duration = "600s"
}