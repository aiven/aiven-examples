#
# Inspired by https://gist.github.com/alexhwoods/4c4c90d83db3c47d9303cb734135130d
#

resource "null_resource" "db_setup" {
  provisioner "local-exec" {
    command = "psql -U ${aiven_pg.pg.service_username} -h ${aiven_pg.pg.service_host} -p ${aiven_pg.pg.service_port} -d ${local.avn_pg_dbname} -f ${path.module}/queries.sql"
    environment = {
      PGPASSWORD = aiven_pg.pg.service_password
      PGSSLMODE  = aiven_pg.pg.pg[0].sslmode
    }
  }

  triggers = {
    db_created = aiven_pg.pg.service_uri
  }

  depends_on = [
    aiven_pg.pg,
    aiven_database.pg_db,
  ]
}