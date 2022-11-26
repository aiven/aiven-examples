# migrate-vpc

This guide shows how-to migrate Aiven services to a different VPC within the same cloud region.  This can be a solution when the network CIDR previously created running out of IPs.

## Requirement

- `avn` CLI
- `terraform`

## Steps

- By default you can only have one VPC per cloud region, please contact Aiven to enable more than one VPC for your project.

- Check the VPCs on your Aiven project with 

```avn vpc list --project project_name```

- When using terraform data source, you can lookup VPCs with only ``project`` and ``cloud_name`` defined, terraform would exit with error when there are multiple VPCs in the same cloud region, returning the avaiable VPCs defined.
```
data "aiven_project_vpc" "vpc2" {
  # to lookup available VPCs in a project, define project and cloud_name below without vpc_id
  project      = var.aiven_project
  cloud_name   = var.cloud_name
}
```

*Please note Aiven console does not support multiple VPCs per same cloud region, it would only show one VPC, please use the above command to see all the VPCs.*

- Create a new VPC using ``avn vpc create`` with the same ``--cloud-name`` and a larger ``--network-cidr`` than the old one. Sizes up to ``/20`` are supported OR use terraform, in the example ``services.tf`` provided, new VPC was added by
```
resource "aiven_project_vpc" "vpc1" {
  project      = var.aiven_project
  cloud_name   = var.cloud_name
  network_cidr = "10.1.0.0/20"

  timeouts {
    create = "5m"
  }
}
```
If you are using datasource instead of resource, define ``vpc_id`` in the following format in ``vpc-data-source.tf``

```
data "aiven_project_vpc" "vpc2" {
  vpc_id = "PROJECT_NAME/VPC_ID"
}
```
OR
You can use ``avn-vpc-datasource.sh`` to generate ``vpc-data-source.tf``, it would lookup all the VPCs in the project and create data-sources with naming convention of ``cidr_IP-CIDR`` for each VPC.


- Create the same peerings for the new VPC has that the old VPC has using avn vpc peering-connection create. Remember to update firewall rules on the user side if they have such things set up

- Migrate each service using the CLI with ``avn service update --project-vpc-id $new_vpc_id`` OR use terraform, in the example ``services.tf`` provided, it migrated from ``vpc0`` to ``vpc1``.
```
  project_vpc_id = project_vpc_id = resource.aiven_project_vpc.vpc1.id 
```
OR if you are using data-source set project_vpc_id to ``data.aiven_project_vpc.key``
```
  project_vpc_id = data.aiven_project_vpc.cidr_10-168-0-0-20.id
```

```
  terraform apply
```