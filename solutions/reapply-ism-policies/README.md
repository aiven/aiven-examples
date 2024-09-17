# Re-apply ISM policies to indices after data migration


When restoring the `.opendistro-ism-config` will only restore the policies themselves,
but the what policies are assigned to what indices is automatically restored. Unlike
opensearch, in opendistro the policy assignments are stored in metadata of the the
cluster state not in the index. When restoring the the snapshot with
`include_global_state: true` the assignments are still present in the cluster state
and can therefore be re-applied.

## Prerequisites

Before starting the migration, ensure the following:

- A machine with network access to Aiven for OpenSearch services
- Python 3.11 or higher installed
- All the indices have been restored from the snapshot
- `.opendistro-ism-config` index has been restored
- all snapshot were restored with `include_global_state: true`

## Re-appying the ISM policies

### Create the configuration file

Create a JSON configuration file with the connection details for the target
(Aiven for OpenSearch) services. Following is an example:

```json
{
    "host": "target-ip-or-fqdn",
    "port": target-port-number,
    "user": "the user",
    "password": "the password"
  }
}
```
It is recommended to use the default aivenadmin user for this task.

### Run the re-apply script

Once your configuration file is ready, run the following command to re-apply the
policies:

```bash
python avn-re-apply-ism-policies.py --config path-to-config-file
```

The script connects to the service, retrieves the metadata from cluster state and
then goes thru it and re-applies the ISM policy to the appropriate index.


### Re-running the script

This script can only be run once as Opensearch will clear the metadata automatically
when the ISM policies are executed the first time.
