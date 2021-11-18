## Intro

This is set of Terraform instructions how to build example services with Aiven.

It is used to demonstrate migration path from TF 0.12 with Aiven provider 1.3.5 to TF 1.0.9+ with Aiven provider 2.1.x

### Service map

```
                                       ┌──────────────┐
                                       │   Kibana     │
                                       │              │
                                       └───────▲──────┘
                                               │
                                       ┌───────┴──────┐
                                       │              │
      ┌────────────Logs────────────────►  OpenSearch  ◄──────────Logs───────────┐
      │                                │              │                         │
      │                                │              ◄─────────────────┐       │
      │                                └───────┬──────┘                 │       │
      │                                        │                        │       │
      │                                        │                        │       │
      │                                 ┌──────▼──────┐  ┌───────────┐  │       │
      │                                 │             │  │           │  │       │
      │                                 │   InfluxDB  ├──►  Grafana  │  │       │
      │      ┌───────Metrics────────────►             │  │           │  │       │
      │      │                          └▲─────▲─────▲┘  └───────────┘  │       │
      │      │                           │     │     │                ┌─┘       │
      │      │                           │     │     │                │         │
      │      │                         ┌─┘     │     │                │      ┌──┴──────┐
      │      │                         │       │     │                │      │         │
      │      │                         │       │     └────Metrics─────┼──────┤  Redis  │
      │      │                         │       │                      │      │         │
      │      │                         │       │                      │      └──────▲──┘
┌─────┴──────┴─┐  ┌────────────────┐   │       │                      │             │
│   Postgres   │  │  Postgres      │   │       │                      │             │
│   Cluster    ├──►  Read Replica  │   │       │                      │             │
│              │  │                ├───┘       │                      │             │
└─────▲────────┘  └────────────────┘           └─┐                    │             │
      │                                          │                    │             │
      │                                          │                    │             │
      │                                          │                    │             │
      │                                       Metrics                 │             │
      │                                          │                    │             │
      │                                          │                    │             │
      │                                      ┌───┴───────────┐        │             │
      │                                      │               │        │             │
      │                                      │   Kafka       │        │             │
      │                                      │               ├─Logs───┘             │
      │                                      │               │                      │
      │                                      └──────▲────────┘                      │
      │                                             │                               │
      │                                    ┌────────┴──────────┐                    │
      │                                    │                   │                    │
      │                                    │    Kafka Connect  │                    │
      │                        ┌───────────┼──────┐        ┌───┼───────────┐        │
      │                        │           │xxxxxx│        │xxx│           │        │
      │                        │           └──────┼────────┼───┘           │        │
      └────────────────────────┤     Debezium     │        │  Redis Sink   ├────────┘
                               │                  │        │               │
                               │                  │        │               │
                               └──────────────────┘        └───────────────┘
```

### How to run

#### Requirements

* [Aiven API token](https://help.aiven.io/en/articles/2370350-aiven-terraform-integration)
* `psql` should be installed locally (*sigh*)
* `make`
* `terraform`
* `tfenv` (Optional)
* `go` (Optional; depending on your Aiven terraform provider version)
* some bitter brew of your choice🥤(Optional)

#### Commands

`make plan`

`make apply`

## Upgrading the Aiven Terraform Provider from v1 to v2

Version 2 of the Aiven Terraform Provider was released in [October of 2020](https://aiven.io/blog/aiven-terraform-provider-v2-release). You may still be running v1 and wanting to upgrade, this guide will walk you through the process (there are quite a few ways to achieve this technically but we will be focusing on only one).

### Notable Changes

- Billing Groups have been introduced instead of needing to provide Card ID
- Work is being done to deprecate `aiven_service` in order to support individual service configuration better, using `aiven_kafka` for example.
- New resources has been added to the Aiven terraform provider, such as `aiven_flink`, `aiven_opensearch`, etc.
- More details of all of the changes can be found in the [Changelog](https://github.com/aiven/terraform-provider-aiven/blob/master/CHANGELOG.md).

### Original Setup

Terraform Version: 0.12.31

Terraform Provider: 1.3.5

To handle the various versions of Terraform, we will be using the great tool: [tfenv](https://github.com/tfutils/tfenv), but you can use direct releases from Hashicorp as you like.

`tfenv install 0.12.31 && tfenv use 0.12.31`

`mkdir example-tf && cd example-tf`

`GO111MODULE=on go install github.com/aiven/terraform-provider-aiven@v1.3.5`

`mkdir -p $PWD/terraform.d/plugins/linux_amd64/`

`cp $GOPATH/bin/terraform-provider-aiven $PWD/terraform.d/plugins/linux_amd64/terraform-provider-aiven_v1.3.5`

Download one of the example scripts and add your variables (or enter them in the Command Line prompt). For example from [here](https://github.com/aiven/aiven-examples/tree/aiven-terraform-v1.3.5) or use the following example from the blog post of the v2 release:

```hcl
terraform {
  # go install github.com/aiven/terraform-provider-aiven@v1.3.5
  # mkdir -p $PWD/terraform.d/plugins/linux_amd64/
  # cp $GOPATH/bin/terraform-provider-aiven \
  #   $PWD/terraform.d/plugins/linux_amd64/terraform-provider-aiven_v1.3.5
  required_providers {
    aiven = "1.3.5"
  }
}

variable "aiven_api_token" {
  type = string
}

provider "aiven" {
  api_token = var.aiven_api_token
}

data "aiven_project" "tf" {
  project = "terror"
}

resource "aiven_service" "kf" {
  project                 = aiven_project.tf.project
  cloud_name              = "google-europe-west1"
  plan                    = "business-4"
  service_name            = var.kafka_svc
  service_type            = "kafka"
  maintenance_window_dow  = "saturday"
  maintenance_window_time = "10:00:00"

  kafka_user_config {
    kafka_connect   = true
    kafka_rest      = true
    kafka_version   = "2.8"
    schema_registry = true

    kafka {
      group_max_session_timeout_ms = 70000
      log_retention_bytes          = 1000000000
      auto_create_topics_enable    = true
    }
    public_access {
      kafka_rest    = true
      kafka_connect = true
      prometheus    = true
    }
  }
}
```

Run:

`terraform init`

`terraform plan`

`terraform apply`


### Upgrade Terraform

**Kick things off with 0.13**

If you are using more providers than Aiven provider and/or your module syntax is 0.12, then you need to upgrade your modules and providers first
by installing terraform v0.13.x (i.e. 0.13.7): `tfenv install 0.13.7 && tfenv use 0.13.7`

You will likely have an existing state file, by running: `terraform state replace-provider registry.terraform.io/-/aiven registry.terraform.io/aiven/aiven` you will replace old Aiven terraform provider references to the new format.

Also update `required_version` from `>= 0.12` to `>= 0.13` in your `versions.tf` file if you have any.

We can remove the old Terraform folder `rm -rf ~/.terraform.d`

Edit the providers block of your script to include the latest version of the Aiven Terraform Provider (v2.3.1 as of 5th November 2021)

```
terraform {
  required_providers {
    aiven = {
      source = "aiven/aiven"
      version = "2.3.1"
    }
  }
}
```

After that you can run: `terraform 0.13upgrade` to see fixes recommended by Hashicorp. More information [here](https://www.terraform.io/upgrade-guides/0-13.html).

**Bump it to the latest**

Any version above 0.13 will be fine, here we use the latest (1.0.10 as of 5th November 2021) `tfenv install latest && tfenv use latest`

Run:

`terraform init -upgrade`

`terraform plan`

![terraform-upgrade.jpg](terraform-upgrade.jpg)

You may see warnings or errors like the above, these will point towards changes made between the release you are running and the latest release.

The warnings will provide recommendations on the changes to make and you can get more information using our [docs](https://registry.terraform.io/providers/aiven/aiven/latest/docs).

### Migrating from `aiven_service` to `aiven_x`

Migration strategy – since `aiven_service` and `aiven_x`, i.e. `aiven_mysql` are different kind of resources just by rewriting code we would cause destructive actions. Also running `terraform state mv <x> <y>` will not do it because it is a different resource type.

So... We would have to change the code first, remove old resource from the state and then import already existing service to the terraform state. Please check below for more information.

**Kafka**

To change from the old `aiven_service` to the new `aiven_kafka` resource, resource type should be changed as well as `service_type` should be removed.

The rest of the configuration parameters stay untouched. Some new configuration parameters might be available, i.e. `kafka_authentication_methods`. And [some](https://github.com/aiven/terraform-provider-aiven/blob/06803836b84197ba2441a685e7758499c800aaab/templates/guides/upgrade-guide.md) could have changed their defaults.

Also all references should be updated from the `aiven_service.kafka.x` to the `aiven_kafka.kafka.x`.

```
- resource "aiven_service" "kafka" {
-    service_type            = "kafka"
+ resource "aiven_kafka" "kafka" {
    ...
}

resource "aiven_service_user" "kafka_user" {
  project      = var.aiven_project_name
-  service_name = aiven_service.kafka.service_name
+  service_name = aiven_kafka.kafka.service_name
  username     = var.kafka_user_name
}
```

**Kafka Connect**

We follow the same principle here as in `aiven_kafka` or any other resource.

```
- resource "aiven_service" "kafka_connect" {
-  service_type            = "kafka_connect"
+ resource "aiven_kafka_connect" "kafka_connect" {
  project                 = var.aiven_project_name
  cloud_name              = var.cloud_name
  service_name            = local.kafka_connect_service_name
  plan                    = "business-4"
  maintenance_window_dow  = "friday"
  maintenance_window_time = "20:30:00"
  termination_protection  = false
  kafka_connect_user_config {
    kafka_connect {
      consumer_isolation_level = "read_committed"
    }
    public_access {
      kafka_connect = true
    }
  }
}

resource "aiven_service_integration" "kafka_connect_integration" {
  project                  = var.aiven_project_name
  integration_type         = "kafka_connect"
  source_service_name      = var.kafka_service_name
-  destination_service_name = aiven_service.kafka_connect.service_name
+  destination_service_name = aiven_kafka_connect.kafka_connect.service_name
}

output "service_name" {
-  value = aiven_service.kafka_connect.service_name
+  value = aiven_kafka_connect.kafka_connect.service_name
}
```

**Postgres**

We follow the same principle here as described above.

```
- resource "aiven_service" "pg" {
-  service_type            = "pg"
+ resource "aiven_pg" "pg" {
  pg_user_config {
    pg_version = "13"
    pg {
      idle_in_transaction_session_timeout = 900
    }
    pgbouncer {
+      autodb_max_db_connections = 200
+      min_pool_size = 50
      server_reset_query_always = false
    }
}

resource "aiven_database" "pg_db" {
  project       = var.aiven_project_name
-  service_name  = aiven_service.pg.service_name
+  service_name  = aiven_pg.pg.service_name
  database_name = local.avn_pg_dbname
}

...

- resource "aiven_service" "pg_read_replica" {
-  service_type            = "pg"
+ resource "aiven_pg" "pg_read_replica" {
  project                 = var.aiven_project_name
  cloud_name              = var.replica_cloud_name
  service_name            = local.replica_service_name
  ...

  service_integrations {
    integration_type    = "read_replica"
-    source_service_name = aiven_service.pg.service_name
+    source_service_name = aiven_pg.pg.service_name
  }

  pg_user_config {
-    service_to_fork_from = aiven_service.pg.service_name
+    service_to_fork_from = aiven_pg.pg.service_name

    pg {
      idle_in_transaction_session_timeout = 900
    }
    ...
  }

  depends_on = [
-    aiven_service.pg,
+    aiven_pg.pg,
  ]
}

```

**Redis**

We follow the same principle here as described above.

```
- resource "aiven_service" "redis" {
-  service_type            = "redis"
+ resource "aiven_redis" "redis" {
  ...
}
```

**InfluxDB**

We follow the same principle here as described above.

```
- resource "aiven_service" "influx" {
-  service_type            = "influxdb"
+ resource "aiven_influxdb" "influx" {
  project                 = var.aiven_project_name
  cloud_name              = var.cloud_name
  service_name            = local.influx_service_name
  ...
}

output "influx_service_uri" {
-  value = aiven_service.influx.service_uri
+  value = aiven_influxdb.influx.service_uri
}

output "influx_service_name" {
-  value = aiven_service.influx.service_name
+  value = aiven_influxdb.influx.service_name
}
```

**Grafana**

We follow the same principle here as described above.

```
- resource "aiven_service" "grafana" {
+ resource "aiven_grafana" "grafana" {
-  service_type           = "grafana"
  project                = var.aiven_project_name
  cloud_name             = var.cloud_name
  service_name           = local.grafana_service_name
  ...
}

output "grafana_service_name" {
-  value = aiven_service.grafana.service_name
+  value = aiven_grafana.grafana.service_name
}
```

**OpenSearch**

We follow the same principle here as described above.

Migrating from ElasticSearch `aiven_service` to `aiven_elasticsearch`:

```
- resource "aiven_service" "opensearch" {
-  service_type            = "elasticsearch"
+ resource "aiven_elasticsearch" "opensearch" {
  project                 = var.aiven_project_name
  cloud_name              = var.cloud_name
  service_name            = local.opensearch_service_name
  plan                    = "startup-8"
  maintenance_window_dow  = "thursday"
  maintenance_window_time = "07:30:00"
  termination_protection  = false

  elasticsearch_user_config {
    elasticsearch_version = 7

    kibana {
      enabled = true
      elasticsearch_request_timeout = 30000
    }

    elasticsearch {
      action_auto_create_index_enabled = true
    }
  }
}

resource "aiven_service_user" "search_user" {
  project      = var.aiven_project_name
  service_name = aiven_elasticsearch.opensearch.service_name
  username     = "os_user"
}

resource "aiven_elasticsearch_acl" "search_acl" {
  project      = var.aiven_project_name
  service_name = aiven_elasticsearch.opensearch.service_name
  enabled      = true
  acl {
    username = aiven_service_user.search_user.username
    rule {
      index      = "_*"
      permission = "admin"
    }
    rule {
      index      = "*"
      permission = "admin"
    }
}
```

Creating OpenSearch `aiven_opensearch` service based on `aiven_elasticsearch`:

```
locals {
  acl_rules = [
    {
      index      = "_*"
      permission = "admin"
    },
    {
      index      = "*"
      permission = "admin"
    }
  ]
}

resource "aiven_opensearch" "opensearch" {
  project                 = var.aiven_project_name
  cloud_name              = var.cloud_name
  service_name            = local.opensearch_service_name
  plan                    = "startup-8"
  maintenance_window_dow  = "thursday"
  maintenance_window_time = "07:30:00"
  termination_protection  = false

-  elasticsearch_user_config {
-    elasticsearch_version = "7"
+  opensearch_user_config {
+    opensearch_version = 1

-    kibana {
+    opensearch_dashboards {
      enabled                    = true
-      elasticsearch_request_timeout = 30000
+      opensearch_request_timeout = 30000
    }

    public_access {
      opensearch            = true
      opensearch_dashboards = true
    }

    ip_filter = ["0.0.0.0/0"]

-    elasticsearch {
+    opensearch {
      action_auto_create_index_enabled = true
    }
  }
}

resource "aiven_service_user" "search_user" {
  project      = var.aiven_project_name
-  service_name = aiven_service.opensearch.service_name
+  service_name = aiven_opensearch.opensearch.service_name
  username     = "os_user"
}

- resource "aiven_elasticsearch_acl" "search_acl" {
+ resource "aiven_opensearch_acl_config" "os_acls_config" {
  project      = var.aiven_project_name
-  service_name = aiven_service.opensearch.service_name
+  service_name = aiven_opensearch.opensearch.service_name
  enabled      = true
+  extended_acl = false
}

resource "aiven_opensearch_acl_rule" "search_acl" {
  for_each = { for i, v in local.acl_rules : i => v }

  project      = var.aiven_project_name
  service_name = aiven_opensearch_acl_config.os_acls_config.service_name
  username     = aiven_service_user.search_user.username
  index        = each.value.index
  permission   = each.value.permission
}

output "opensearch_service_uri" {
-  value = aiven_service.opensearch.elasticsearch[0].kibana_uri
+  value     = aiven_opensearch.opensearch.opensearch[0].opensearch_dashboards_uri
  sensitive = true
}

output "opensearch_service_name" {
-  value = aiven_service.opensearch.service_name
+  value = aiven_opensearch.opensearch.service_name
}
```

More information regarding migration from ElasticSearch to OpenSearch could be found [here](https://help.aiven.io/en/articles/5424825-upgrading-elasticsearch-services-to-aiven-for-opensearch).

**Etc**

To check more detailed code diff please refer to this [link](https://github.com/aiven/aiven-examples/compare/aiven-terraform-v1.3.5...aiven-terraform-v2.3.2).

Example of the migration steps:

```
$ terraform state list | grep mysql
$ terraform state rm aiven_service.mysql

$ terraform import aiven_mysql.mysql mischa-demo/mysql-test-b00ba
$ terraform plan
$ terraform apply
```

More detailed description of `terraform import` could be found at official documentation [site](https://www.terraform.io/docs/cli/commands/import.html).

### Thank you

If you have any issues, please contact us at [support@aiven.io](mailto:support@aiven.io?subject=Terraform%20Provider%20v2&body=👋)

🙇
