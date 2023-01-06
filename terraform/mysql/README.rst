Aiven Terraform Script for MySQL-DataDog integration
======================================================

This example implements a terraform script to create and perform MySQL and datadog service integration.

The Terraform provider for `Aiven.io <https://aiven.io/>`_, an open source data platform as a service.

See the `official documentation <https://registry.terraform.io/providers/aiven/aiven/latest/docs>`_ to learn about all the possible services and resources.

Quick start
------------

1. `Signup for Aiven <https://console.aiven.io/signup?utm_source=github&utm_medium=organic&utm_campaign=terraform&utm_content=signup>`_
2. Get your `authentication token and project name <https://docs.aiven.io/docs/platform/concepts/authentication-tokens>`_

3. Download the following files provider.tf, variables.tf, mysql-datadog.tf
4. Update the following variables in **variables.tf** file according to requirements:

    * cloud_name
    * mysql_plan
    * endpoint_name
    * datadog_site
    * tag
    * mysql_service

5. Run these commands in your terminal and follow the instructions on the terminal:

    * terraform init
    * terraform plan
    * terraform apply

6. When prompted, enter the values for:

    * aiven_api_token (Can be created from Aiven console under User Information -> Authentication -> Generate tokens)
    * datadog_api_key (Can be found from Datadog console under User -> Organization Settings -> API Keys)
    * datadog_app_key (Can be created from Datadog console under User -> Organization Settings -> Application Keys)
    * project_name

7. Once completed, check if the following actions have been executed on the console:

    * A new MySQL service is created
    * A new Datadog endpoint is created
    * MySQL service is integrated with the new datadog endpoint
