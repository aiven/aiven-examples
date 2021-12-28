## Azure virtual network peering with Aiven

This script automates the steps from this article 
https://help.aiven.io/en/articles/3435096-azure-virtual-network-peering


Make sure to log in with an Azure account with at least *Application administrator role*, or else step 7 will fail.


Open the article link and start the script, which will walk you through the steps in the article:
```bash
# navigate your terminal to sa-solution-code-samples/azure-vnet-peering directory
docker run -it --rm \
    -v $PWD/create_peering.sh:/usr/local/bin/create_peering:ro \
    --name=azure-aiven-peering \
    mcr.microsoft.com/azure-cli
# at this point you're inside docker container
# you can now run the script
create_peering
```

Everything that's needed and mentioned in the article will be printed out on the standard output.

There are two additional steps bundled into Step 1 that are not mentioned in the article. These are VNet creation (step 1A) and `avn` CLI setup and login (step 1B).

Note that while the script runs, it creates one or more `.json` files containing the output of the executed commands.


## Handling errors or starting from scratch
If something goes wrong, or you just what to reset and start all over again, you'd probably want to clean things up first.\
Note that if step 13 failed, you would most likely have to log in into your main Azure account again with `az account clear && az login`

**Make sure you're still inside the docker container.**

1) clean up step 2 (this also indirectly cleans up step 3):
```bash
# list all app objects
az ad app list | jq -r '.[] | .appId + "   " + .displayName'
# from the list above, delete the one that you created in step 2
az ad app delete --id APP_ID
```
2) clean up step 7
```bash
# delete the Aiven app object from your AD
az ad sp delete --id 55f300d4-fc50-4c5e-9222-e90a6e2187fb
```
3) clean up step 8
```bash
# list all `Microsoft.Network/virtualNetworks/peer/action` role definitions
az role definition list | jq -c '.[]' | grep 'Microsoft.Network/virtualNetworks/peer/action' | jq -r '.roleName'
# from the list above, delete the one that you created in step 8
az role definition delete --name ROLE_NAME
```
4) delete all state files
```
rm *.json
```
