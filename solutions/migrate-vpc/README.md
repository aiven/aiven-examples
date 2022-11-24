# migrate-vpc

This guide shows how-to migrate Aiven services to a different VPC within the same cloud region.  This can be a solution when the network CIDR previously created running out of IPs.

## Requirement

- `avn` CLI
- `terraform`

## Steps

- By default you can only have one VPC per cloud region, please contact Aiven to enable more than one VPC for your project.

- Check the VPCs on your Aiven project with 

```avn vpc list --project project_name```

*Please note Aiven console does not support multiple VPCs per same cloud region, it would only show one VPC, please use the above command to see all the VPCs.*

If your ``terraform.tfstate`` does not have all the VPCs already created, you can use ``avn-import-vpc.sh project_name`` to import your VPCs into ``terraform.tfstate``

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

- Create the same peerings for the new VPC has that the old VPC has using avn vpc peering-connection create. Remember to update firewall rules on the user side if they have such things set up

- Migrate each service using the CLI with ``avn service update --project-vpc-id $new_vpc_id`` OR use terraform, in the example ``services.tf`` provided, it migrated from ``vpc0`` to ``vpc1``.
```
  project_vpc_id = aiven_project_vpc.vpc1.id 
```
```
  terraform apply
```