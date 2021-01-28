import time
import pulumi
import pulumi_aiven as aiven


# Edit instance names, regions and # of read replicas as needed
primary = {'name': "pulumi-pg-master", 'region': "google-us-east1"}
replicas = [
    {'name': "pulumi-pg-replica1", 'region': "google-us-west1"},
    {'name': "pulumi-pg-replica2", 'region': "google-europe-west1"}
]


# Print out connection info
def export_details(avn, prefix):
    pulumi.export(prefix + "_uri", avn.service_uri)
    pulumi.export(prefix + "_username", avn.service_username)
    pulumi.export(prefix + "_password", avn.service_password)
    pulumi.export(prefix + "_state", avn.state)


# Create service in Aiven
def create_postgres(conf, instance_info, integrations=None):
    # Optionally specify the Postgres major version
    user_config_args = aiven.PgPgUserConfigArgs(pg_version=conf.require('pg_version'))
    avn = aiven.Pg(instance_info['name'],
                   project=conf.require('aiven_project'),
                   cloud_name=instance_info['region'],
                   service_name=instance_info['name'],
                   plan=conf.require('plan_size'),
                   pg_user_config=user_config_args,
                   service_integrations=integrations
                   )
    export_details(avn, instance_info['name'])
    return avn


def replica_integration(instance):
    # Specify the read replica service integration
    return aiven.ServiceServiceIntegrationArgs(
        integration_type="read_replica",
        source_service_name=instance.service_name
    )


def main():
    # Read configuration settings
    conf = pulumi.Config()

    # Create primary instance
    pg_master = create_postgres(conf, primary)
    integrations = [replica_integration(pg_master)]

    # Create read replicas
    for replica in replicas:
        create_postgres(conf, replica, integrations)


if __name__ == "__main__":
    main()
