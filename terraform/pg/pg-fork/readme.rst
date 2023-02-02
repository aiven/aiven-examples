Aiven Terraform Script for Postgres DB fork
======================================================

This example implements a terraform script to perform a Postgres fork from an existing database.

Quick start
------------

1. `Signup for Aiven <https://console.aiven.io/signup?utm_source=github&utm_medium=organic&utm_campaign=terraform&utm_content=signup>`_
2. Download the following files provider.tf, variables.tf, service.tf
3. Update the following variables in **variables.tf** file according to requirements:

    * cloud_name
    * pg_plan
    * service_name

4. Run these commands and follow the instructions on the terminal:

    * terraform init
    * terraform plan
    * terraform apply

5. When prompted, enter the values for:

    * aiven_api_token (Can be created from Aiven console under User Information -> Authentication -> Generate tokens)
    * avn_project
    * pg_service_to_fork_from

6. Once completed, check if the following actions have been executed on the console:

    * A new PG fork from an existing DB on the console
    * Data successfuly populated in the forked pg DB