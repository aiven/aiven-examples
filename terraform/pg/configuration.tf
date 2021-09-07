#
# Inspired by https://gist.github.com/alexhwoods/4c4c90d83db3c47d9303cb734135130d
#
# https://github.com/hashicorp/terraform/issues/2430 :(
#

# provider "postgresql" {
#   host            = aiven_service.pg.service_host
#   port            = aiven_service.pg.service_port
#   database        = local.avn_pg_dbname
#   username        = aiven_service.pg.service_username
#   password        = aiven_service.pg.service_password
#   sslmode         = aiven_service.pg.pg[0].sslmode
#   connect_timeout = 15
# }

# resource "postgresql_extension" "avn_extras" {
#   name     = "aiven_extras"
#   database = local.avn_pg_dbname
#   #create_cascade = true

#   depends_on = [
#     aiven_service.pg,
#   ]
# }

# Enable after migration to 0.13+
# provider "sql" {
#   alias = "postgres"
#   url   = aiven_service.pg.service_uri
# }

# data "sql_query" "dbz_publication" {
#   query = "SELECT * FROM aiven_extras.pg_create_publication_for_all_tables('dbz_publication', 'INSERT,UPDATE,DELETE');"
#   depends_on = [
#     postgresql_extension.avn_extras,
#   ]
# }

# Disable after migration to >=0.13+ and remove requirement for `psql` to be installed locally
resource "null_resource" "db_setup" {
  provisioner "local-exec" {
    command = "psql -U ${aiven_service.pg.service_username} -h ${aiven_service.pg.service_host} -p ${aiven_service.pg.service_port} -d ${local.avn_pg_dbname} -f ${path.module}/queries.sql"
    environment = {
      PGPASSWORD = aiven_service.pg.service_password
      PGSSLMODE  = aiven_service.pg.pg[0].sslmode
    }
  }

  triggers = {
    db_created = aiven_service.pg.service_uri
  }

  depends_on = [
    aiven_service.pg,
    # postgresql_extension.avn_extras,
  ]
}