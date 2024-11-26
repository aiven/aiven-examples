# Terraform plan for Aiven resources

This plan will create a bunch of services within your Aiven project
- Kafka
- Kafka Connect Cluster
- PostgreSQL source connector for Kafka Connect
- PostgreSQL database
- Topics, Users and ACLs for Kafka
- M3 Time Series database

You should copy the ```secrets.tfvars.template``` file to ```secrets.tfvars``` and fill in your Aiven project name, token and cloud region. After that you can run

```
terraform apply -var-file=secrets.tfvars
```
