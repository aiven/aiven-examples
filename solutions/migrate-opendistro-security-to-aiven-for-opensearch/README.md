# Opendistro security migration to Aiven for Opensearch

Migrate your security configuration from an Opendistro service to Aiven for OpenSearch® using a migration script.

The `.opendistro_security` index, which stores security settings, cannot be restored
directly from an external snapshot. Instead, you use a migration script that interacts
with the security REST API of both services.

## What is migrated

The migration script transfers the security configuration from the source Opendistro
service to Aiven for OpenSearch. The following configurations are migrated:

- Internal users (including passwords)
- Action groups
- Roles
- Backend roles
- Tenants

The following configurations are **not** migrated:

- Reserved, static, or hidden entries
- Authentication methods and backend configurations, as these are configured differently
  in Aiven for OpenSearch

## Prerequisites

Before starting the migration, ensure the following:

- A machine with network access to both Opendistro and Aiven for OpenSearch services
- Python 3.11 or higher installed
- [Security management](/docs/products/opensearch/howto/enable-opensearch-security)
  enabled on Aiven for OpenSearch
- Admin user certificate and key from the source Opendistro service in PEM format
- Opendistro security configuration version 2
- HTTPS enabled on both services (the script does not verify server certificates)

:::note

- The admin user key and certificate are required to migrate internal users and their
  passwords. The password hash must be fetched directly from the `.opendistro_security`
  index, as the standard API endpoint does not return it.
- The script assumes HTTPS is enabled on both the source and target services.

:::

## Migration steps

To migrate your security configuration from Opendistro to Aiven for OpenSearch:

### Create the migration configuration file

Create a JSON configuration file with the connection details for the source (Opendistro)
and target (Aiven for OpenSearch) services. Following is an example:

```json
{
  "source": {
    "host": "source-ip-or-fqdn",
    "port": source-port-number,
    "key": "path-to-admin-key.pem",
    "certificate": "path-to-admin-cert.pem"
  },
  "target": {
    "host": "target-ip-or-fqdn",
    "port": target-port-number,
    "password": "os-sec-admin-user-password"
  }
}
```

### Run the migration script

Once your configuration file is ready, run the following command to execute the
migration:

```bash
python avn-migrate-os-security-config.py --config path-to-config-file
```

The script connects to both services and starts migrating security configurations. It
logs which entries (roles, role mappings, action groups, tenants, and internal users)
are added or updated. If an entry already exists on the target service, the script skips
it and marks it as unchanged.

### Re-running the script

You can run the migration script multiple times, but keep the following in mind:

- Previously migrated entries are not deleted from the target service.
- Internal user data is updated each time the script is run because the Opendistro
  API does not return password hashes. As a result, the script treats the data as if it
  has changed, even when it has not.

