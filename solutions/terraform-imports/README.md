With a little bit of hackery, terraform import  can make it super easy to clone or move infra....
You can save a bunch of work with config generation, but it has a few defects currently.

Currently, it seems to have issues with non-default whitelists (a known issue with a fix en route) and thanos resource is in the beta stage and may change without notice. 

Set the `PROVIDER_AIVEN_ENABLE_BETA` environment variable to use the resource: 
`export PROVIDER_AIVEN_ENABLE_BETA=1`

But let's show how this works:

This function simply dumps the services for a given project --
```
function projectServices() {
  curl -s --request GET \
  --url "https://api.aiven.io/v1/project/${1}/service" \
  --header "Authorization: Bearer ${AIVEN_API_TOKEN}" \
  --header 'content-type: application/json' \
}
```

This one rewites the output to terraform imports -- 
```
function generateImports() {
  projectServices ${1} | \
  jq -r --arg PROJECT ${1} '.services[]|"import {\n to = aiven_"+ .service_type + "." + .service_name + "\n id = \"" + $PROJECT + "/" + .service_name + "\"\n}"'
}
```

So, let's clone some infra.

Generate the import statements
`tfImports <project_name> > <project_name>.imports.tf`

Initialize Terraform
`terraform init`

Generate a plan from the imports:
`terraform plan -generate-config-out=<project_name>.tf`

Check the results:
```
Plan: 8 to import, 0 to add, 0 to change, 0 to destroy.
```

Import the objects:
`terraform apply`
```
aiven_pg.data-pipeline-test-dvd-rental-pg: Importing... [id=data-pipeline-gcp/data-pipeline-test-dvd-rental-pg]
aiven_pg.data-pipeline-test-dvd-rental-pg: Import complete [id=data-pipeline-gcp/data-pipeline-test-dvd-rental-pg]
aiven_grafana.grafana-obs: Importing... [id=data-pipeline-gcp/grafana-obs]
aiven_grafana.grafana-obs: Import complete [id=data-pipeline-gcp/grafana-obs]
aiven_pg.pg-mig-test: Importing... [id=data-pipeline-gcp/pg-mig-test]
aiven_pg.pg-mig-test: Import complete [id=data-pipeline-gcp/pg-mig-test]
aiven_clickhouse.data-pipeline-test-dvd-rental-clickhouse: Importing... [id=data-pipeline-gcp/data-pipeline-test-dvd-rental-clickhouse]
aiven_clickhouse.data-pipeline-test-dvd-rental-clickhouse: Import complete [id=data-pipeline-gcp/data-pipeline-test-dvd-rental-clickhouse]
aiven_pg.pg-mig-test-rep: Importing... [id=data-pipeline-gcp/pg-mig-test-rep]
aiven_pg.pg-mig-test-rep: Import complete [id=data-pipeline-gcp/pg-mig-test-rep]
aiven_kafka.data-pipeline-test-dvd-rental-kafka: Importing... [id=data-pipeline-gcp/data-pipeline-test-dvd-rental-kafka]
aiven_kafka.data-pipeline-test-dvd-rental-kafka: Import complete [id=data-pipeline-gcp/data-pipeline-test-dvd-rental-kafka]
aiven_flink.data-pipeline-test-dvd-rental-flink: Importing... [id=data-pipeline-gcp/data-pipeline-test-dvd-rental-flink]
aiven_flink.data-pipeline-test-dvd-rental-flink: Import complete [id=data-pipeline-gcp/data-pipeline-test-dvd-rental-flink]
aiven_m3db.m3db-obs: Importing... [id=data-pipeline-gcp/m3db-obs]
aiven_m3db.m3db-obs: Import complete [id=data-pipeline-gcp/m3db-obs]

Apply complete! Resources: 8 imported, 0 added, 0 changed, 0 destroyed.
```

We now have stateful control of the objects.
`terraform state list`
```
aiven_clickhouse.data-pipeline-test-dvd-rental-clickhouse
aiven_flink.data-pipeline-test-dvd-rental-flink
aiven_grafana.grafana-obs
aiven_kafka.data-pipeline-test-dvd-rental-kafka
aiven_m3db.m3db-obs
aiven_pg.data-pipeline-test-dvd-rental-pg
aiven_pg.pg-mig-test
aiven_pg.pg-mig-test-rep
```


And you can checkout the entire plan and export it if you like:
`terraform show`

...change projects and import where you like.

The functions include some other helpers.

Import project:
`tfImport <project_name>`

Clear existing state / imports:
`tfClear`
