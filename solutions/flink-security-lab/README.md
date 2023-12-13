# Flink Security Lab Demo

This demo leverage Apache Flink to process user logging events sourced from Kafka. The pipeline comprises two key Flink jobs: the first aggregates events in 30-second intervals, storing results in a PostgreSQL table, and the second extracts valuable insights by filtering login events with multiple distinct IPs and sinking these  data into an OpenSearch index. This setup facilitates real-time analysis of security patterns, from `kafka -> flink -> postgres -> flink -> opensearch` for uncovering and visualizing suspicious login activities. Try this demo to see the seamless integration and efficient data processing capabilities of this end-to-end security solution live under 10 minutes.


## Requirement

- `avn` 
- `curl`
- `jq`

## Steps

- Update the `PROJECT` in `lab.env`, the following are configurable:

| Tables                 | Description                 |
| ---------------------- |:---------------------------:|
| PROJECT                | project name                |
| SERVICE                | service name                |
| SERVICE_FLINK          | flink service name          |  
| SERVICE_KAFKA          | kafka service name          |
| SERVICE_OS             | opensearch service name     |
| SERVICE_PG             | postgres search name        |


- Run `cd terraform && terraform init && terraform apply && cd ..`, 
```
cd terraform && terraform init && terraform apply && cd ..
```

- Run `./lab.sh setup`, this would setup kcat configuration, postgres table and opensearch mapping required for this demo. 
```
./lab.sh setup
```

- Go to aiven console, `securitylab-flink` service -> `Applications` -> `pg-audit-logs` -> `Create deployment`.

- Run `./lab.sh demo` to generate user logging events into `securitylab-kafka`'s `security_logs` topic.  This process does not exit until `CTRL + C`, *please keep this process and terminal running through out the entire demo.*
```
./lab.sh demo
```

- Event data can be viewed under topics in kafka `securitylab-kafka` and postgres `securitylab-pg`
```
echo "select * from audit_logs;" | psql $(avn service get securitylab-pg --format "{service_uri}")
```


- Go to aiven console, `securitylab-flink` service -> `Applications` -> `os-suspecious-logins` -> `Create deployment`.


- Login to `security-os` OpenSearch Dashboard -> `Dev Tools`, the following call would show if data are coming in.
```
GET /suspecious-logins/_search
```


- OpenSearch Dashboard -> `Discover` -> `Create index pattern` -> `suspecious-logins` to index pattern name `Next step` -> Time field `time_stamp` -> `Create index pattern`.  Click on `Discover` again and filtered suspecious login entries should be presented on OpenSearch Dashboard.


- Run `./lab.sh teardown` to delete all the resources created from this demo.  Note: this would cause `terraform.tfstate` out of sync which would have to be deleted after.
```
./lab.sh teardown
```
