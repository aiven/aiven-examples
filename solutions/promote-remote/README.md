

## Aim:
Creation of an Aiven for PostgreSQL in one cloud region with a remote read replica in another cloud region. Using a simple monitoring script, we can check if the primary is available and make a manual edit to promote the replica upon failure to connect
Useful links:
- https://help.aiven.io/en/articles/5372422-terraform-to-apply-promote-to-master-on-postgresql-mysql-replica


## Using Terraform

Deploying a Primary and Remote Read Replica

```
resource "aiven_pg" "pg-jakarta" {
 project      = data.aiven_project.sample.project
 cloud_name   = "google-asia-southeast2"
 plan         = "startup-4"
 service_name = "pg-jakarta"
 pg_user_config {
   pg_version = 14
   public_access {
     pg         = true
   }
 }
 
}
 
resource "aiven_pg" "pg-aws" {
 project                 = data.aiven_project.sample.project
 cloud_name              = "aws-ap-southeast-1"
 service_name            = "pg-aws"
 plan                    = "startup-4"
 maintenance_window_dow  = "saturday"
 maintenance_window_time = "07:45:00"
 termination_protection  = false
 
 service_integrations {
   integration_type    = "read_replica"
   source_service_name = aiven_pg.pg-jakarta.service_name
 }
 
 pg_user_config {
   service_to_fork_from = aiven_pg.pg-jakarta.service_name
 }
 
 depends_on = [
   aiven_pg.pg-jakarta,
 ]
}
resource "aiven_service_integration" "pg-readreplica" {
 project = data.aiven_project.sample.project
 integration_type = "read_replica"
 source_service_name = aiven_pg.pg-jakarta.service_name
 destination_service_name = aiven_pg.pg-aws.service_name
}
 

resource "aiven_grafana" "grafana-jakarta" {
 project      = data.aiven_project.sample.project
 cloud_name   = "google-asia-southeast1"
 plan         = "startup-4"
 service_name = "grafana-jakarta"
 grafana_user_config {
   ip_filter = ["0.0.0.0/0"]
 }
}
```

TODO Add cloud function to TF script
TODO Add metrics (m3) integration to Primary and Remote to go to Grafana

## Monitoring your Primary

1. Deploy a Google Cloud Function to act as a webhook triggered by HTTP call to remove service integration
2. Using Grafana dashboards and alerting rules
3. Call webhook after 3 failed 60s requests 




## Demo Runbook

1. Apply TF plan
2. Show Primary and Remote in Aiven Console
3. Show M3 service and Grafana dashboard for service metrics
4. Add grafana alerting rule
5. Power off Primary DB in Aiven Console
6. Wait for webhook to be triggered
7. Show Remote in Console promoted to Primary


## Additional points: 
- Mention that their end application needs to change URL if entire cloud cluster fails 
- Mention that the situation is rare due to nodes being spread across multiple AZs when using a Business/Premium plan

