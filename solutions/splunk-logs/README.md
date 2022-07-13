An example to capture logs from an Aiven service (e.g. Kafka) push those 
logs to another Kafka and then use Kafka Connect to push those logs to Splunk

Create a teeraform.tfvars file and fill in the following values
- aiven_api_token: A token generated from the CLI or console
- aiven_project_name: Name of project to deploy to
- service_prefix: Prefix for all services created
- cloud: Cloud region to deploy to
- splunk_hec_uri = HEC URI for HTTP Event Collector
- splunk_hec_token = HTTP Event Collector token for Event Collector
