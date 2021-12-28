#!/bin/bash

##### THIS SCRIPT IS INTENDED TO RUN ON DOCKER ########
# docker run -it --rm -v $PWD/create_peering.sh:/vpc.sh:ro --name=azure-vpc mcr.microsoft.com/azure-cli
#################################

SPIN_STRING='-\|/'

########################################################################
printf '### Step 1\n'
stdouttmp=$(az account show 2>/dev/null)
if test -z "$stdouttmp"
then
    printf '************************************************\n* Make sure to log in with an account with at least Application administrator role, or else step 7 will fail!\n************************************************\n'
    az login
    # pick subscription
    stdouttmp=$(az account list -all| jq length)
    if [ $stdouttmp == "0" ]
    then
        echo "No subscriptions" >&2; exit 1
    elif [ $stdouttmp != "1" ]
    then
        echo 'Subscriptions:'
        az account list --all | jq -r '.[] | .id + "   " + .name + "   " + .user .name'
        read -p "Enter subscription ID you want to use: " account_subscription_id
        echo "$account_subscription_id"
        az account set --subscription "$account_subscription_id"
        if test $? -ne 0
        then
            echo "Invalid subscription" >&2; exit 1
        fi
    fi
else
    azure_user_email=$(echo $stdouttmp | jq -r '.user .name')
    echo "Logged in as $azure_user_email"
fi


########################################################################
printf '\n\n### Step 1A - VNet check/creation\n'
read -p "Enter VNet name to peer with: " vnet_name
stdouttmp=$(az network vnet list | jq ".[] | select(.name==\"$vnet_name\")")
if test -z "$stdouttmp"
then
    read -p "[$vnet_name] is not found. Do you wan't to create [$vnet_name] (y/n)? " stdouttmp
    if [ $stdouttmp == "y" ]
    then
        printf "Azure locations:\n southafricanorth (Africa, South Africa)\n eastasia (Asia, Hong Kong)\n indiacentral (Asia, India)\n indiasouth (Asia, India)\n indiawest (Asia, India)\n japaneast (Asia, Japan)\n japanwest (Asia, Japan)\n koreacentral (Asia, Korea)\n koreasouth (Asia, Korea)\n southeastasia (Asia, Singapore)\n australiacentral (Australia, Canberra)\n australiaeast (Australia, New South Wales)\n australiasoutheast (Australia, Victoria)\n canadacentral (Canada, Ontario)\n canadaeast (Canada, Quebec)\n uksouth (Europe, England)\n francecentral (Europe, France)\n germanynorth (Europe, Germany)\n germanywestcentral (Europe, Germany)\n northeurope (Europe, Ireland)\n westeurope (Europe, Netherlands)\n norwayeast (Europe, Norway)\n norwaywest (Europe, Norway)\n switzerlandnorth (Europe, Switzerland)\n ukwest (Europe, Wales)\n uaenorth (Middle East, United Arab Emirates)\n brazilsouth (South America, Brazil)\n westus (United States, California)\n northcentralus (United States, Illinois)\n centralus (United States, Iowa)\n southcentralus (United States, Texas)\n eastus (United States, Virginia)\n eastus2 (United States, Virginia)\n westus2 (United States, Washington)\n westcentralus (United States, Wyoming)\n"
        read -p "Enter location: " location
        read -p "Enter resource group: " resource_group
        stdouttmp=$(az group list | jq ".[] | select(.name==\"$resource_group\") | select(.location==\"$location\")")
        if test -z "$stdouttmp"
        then
            echo " resource group [resource_group] not found, creating it now..."
            stdouttmp=$(az group create --location $location --resource-group $resource_group)
            if test -z "$stdouttmp"
            then
                echo "Failed to create resource group" >&2; exit 1
            fi
        fi
        read -p "Enter VNet CIDR (example '10.139.0.0/16'): " vnet_cidr
        read -p "Enter VNet subnet name (subnet-$vnet_name): " subnet_name
        if test -z "$subnet_name"
        then
            subnet_name="subnet-$vnet_name"
        fi
        read -p "Enter VNet subnet CIDR (example '10.139.1.0/24'): " subnet_cidr
        echo " creating VNet..."
        stdouttmp=$(az network vnet create --address-prefixes $vnet_cidr --name $vnet_name --resource-group $resource_group --subnet-name $subnet_name --subnet-prefixes $subnet_cidr)
        if test -z "$stdouttmp"
        then
            echo "Failed to create VNet $vnet_name" >&2; exit 1
        fi
        sleep 15 # wait a bit more so that the VNet is really ready
        echo " done"
    else
        echo "You must have a valid VPC to enable peering" >&2; exit 1
    fi
fi


########################################################################
printf '### Step 1B - Aiven login\n'
if ! command -v avn &> /dev/null
then
    echo "Aiven CLI not found, installing it now..."
    python3 -m pip install aiven-client
fi
# skip if user is already logged in
stdouttmp=$(avn user info 2>/dev/null)
if test -z "$stdouttmp"
then
    read -p "Enter your Aiven account email: " aiven_email
    read -p "Do you want to use token to login (y/n)? " use_token
    if [ $use_token == "y" ]
    then
        echo "Enter your Aiven token when prompted"
        avn user login "$aiven_email" --token
        # read -p "Enter your Aiven token: " aiven_token
        # mkdir -p ~/.config/aiven
        # echo "{\"auth_token\": \"$aiven_token\", \"user_email\": \"$aiven_email\"}" > ~/.config/aiven/aiven-credentials.json
    else
        echo "Enter your Aiven password when prompted"
        avn user login "$aiven_email"
    fi
    stdouttmp=$(avn user info 2>/dev/null)
    if test -z "$stdouttmp"
    then
        echo "Invalid Aiven login" >&2; exit 1
    fi
fi


########################################################################

printf '\n\n### Step 2\n'
read -p "Enter app name (vpc_api_aiven): " vpc_app_display_name
if test -z "$vpc_app_display_name"
then
    vpc_app_display_name="vpc_api_aiven"
fi
echo 'creating app...'
stdouttmp=$(az ad app create --display-name $vpc_app_display_name --available-to-other-tenants --key-type Password)
if test -n "$stdouttmp"
then
    echo $stdouttmp > step02_app_create.json
    sleep 15
fi
user_app_id=$(cat step02_app_create.json | jq -r '.appId')
if test -z "$user_app_id"
then
    echo "Invalid user_app_id" >&2; exit 1
fi
echo "user_app_id=$user_app_id"


########################################################################
printf '\n\n### Step 3\n'
echo 'checking if service principal already exists'
stdouttmp=$(az ad sp list | jq ".[] | select(.appId==\"$user_app_id\")")
if test -n "$stdouttmp"
then
    echo $stdouttmp > step03_service_principal_app.json
else
    echo 'creating new service principal...'
    stdouttmp=$(az ad sp create --id $user_app_id)
    if test -n "$stdouttmp"
    then
        echo $stdouttmp > step03_service_principal_app.json
        sleep 3
    fi
fi
user_sp_id=$(cat step03_service_principal_app.json | jq -r '.objectId')
if test -z "$user_sp_id"
then
    echo "Invalid user_sp_id" >&2; exit 1
fi
echo "user_sp_id=$user_sp_id"

########################################################################
printf '\n\n### Step 4\n'
stdouttmp=$(az ad app credential reset --id $user_app_id)
if test -n "$stdouttmp"
then
    echo $stdouttmp > step04_app_credential.json
    sleep 3
fi
user_app_secret=$(cat step04_app_credential.json | jq -r '.password')
if test -z "$user_app_secret"
then
    echo "Invalid user_app_secret" >&2; exit 1
fi
echo "user_app_secret=$user_app_secret"


########################################################################
printf '\n\n### Step 5\n'
stdouttmp=$(az network vnet list | jq ".[] | select(.name==\"$vnet_name\")")
if test -z "$stdouttmp"
then
    echo "Can't find VNet $vnet_name" >&2; exit 1
fi
echo $stdouttmp > step05_network_vnet_list.json
user_vnet_id=$(jq -r '.id' step05_network_vnet_list.json)
user_subscription_id=$(echo $user_vnet_id | cut -d / -f 3)
user_resource_group=$(echo $user_vnet_id | cut -d / -f 5)
user_vnet_name=$(echo $user_vnet_id | cut -d / -f 9)
echo "user_vnet_id=$user_vnet_id"
echo "user_subscription_id=$user_subscription_id"
echo "user_resource_group=$user_resource_group"
echo "user_vnet_name=$user_vnet_name"


########################################################################
printf '\n\n### Step 6\n'
az role definition list --name "Network Contributor" > step06_1_network_contributor.json
network_contributor_role_id=$(jq -r '.[0].id' step06_1_network_contributor.json)
if test -z "$network_contributor_role_id"
then
    echo "Invalid network_contributor_role_id" >&2; exit 1
fi
echo "network_contributor_role_id=$network_contributor_role_id"
stdouttmp=$(az role assignment create --role $network_contributor_role_id --assignee-object-id $user_sp_id --scope $user_vnet_id)
if test -n "$stdouttmp"
then
    echo $stdouttmp > step06_2_role_assignment_create.json
fi


########################################################################
printf '\n\n### Step 7\n'
# check if it already exists
stdouttmp=$(az ad sp list --filter "appId eq '55f300d4-fc50-4c5e-9222-e90a6e2187fb'" | jq length)
if [ $stdouttmp == "1" ]
then
    az ad sp list --filter "appId eq '55f300d4-fc50-4c5e-9222-e90a6e2187fb'" | jq '.[0]' > step07_service_principal_aiven.json
else
    echo 'creating service principal for the Aiven app object...'
    stdouttmp=$(az ad sp create --id 55f300d4-fc50-4c5e-9222-e90a6e2187fb)
    if test -n "$stdouttmp"
    then
        echo $stdouttmp > step07_service_principal_aiven.json
        sleep 3
    fi
fi
aiven_sp_id=$(jq -r '.objectId' step07_service_principal_aiven.json)
if test -z "$aiven_sp_id"
then
    echo "Failed to create Aiven service principal" >&2; exit 1
fi
echo "aiven_sp_id=$aiven_sp_id"


########################################################################
printf '\n\n### Step 8\n'
read -p "Enter custom role name for the Aiven app object (role_aiven_vpc): " role_definition_name
if test -z "$role_definition_name"
then
    role_definition_name="role_aiven_vpc"
fi
stdouttmp=$(az role definition create --role-definition "{\"Name\": \"$role_definition_name\", \"Description\": \"Allows creating a peering to vnets in scope (but not from)\", \"Actions\": [\"Microsoft.Network/virtualNetworks/peer/action\"], \"AssignableScopes\": [\"/subscriptions/$user_subscription_id\"]}")
if test -n "$stdouttmp"
then
    echo $stdouttmp > step08_role_definition.json
fi
aiven_role_id=$(jq -r '.id' step08_role_definition.json)
if test -z "$aiven_role_id"
then
    echo "Failed to create role definition" >&2; exit 1
fi
echo "aiven_role_id=$aiven_role_id"


########################################################################
printf '\n\n### Step 9\n'
echo 'assign the custom role to the Aiven service principal...'
stdouttmp=$(az role assignment create --role $aiven_role_id --assignee-object-id $aiven_sp_id --scope $user_vnet_id)
if test -n "$stdouttmp"
then
    echo $stdouttmp > step09_role_assignment_create.json
else
    echo "Failed to create role assignment" >&2; exit 1
fi


########################################################################
printf '\n\n### Step 10\n'
user_tenant_id=$(az account list | jq -r '.[0].tenantId')
if test -z "$user_tenant_id"
then
    echo "Invalid user_tenant_id" >&2; exit 1
fi
echo "user_tenant_id=$user_tenant_id"


########################################################################
printf '\n\n### Step 11\n'
avn project list
read -p "Enter your Aiven project name for peering: " aiven_project_name
printf '\n'
read -p "Make sure you've created VPC in the project [$aiven_project_name], press ENTER to continue"
printf '\n'
avn vpc list --project $aiven_project_name
read -p "Enter your Aiven project VPC id: " aiven_project_vpc_id
user_resource_group_lower_case=$(echo $user_resource_group | tr '[:upper:]' '[:lower:]')
user_vnet_name_lower_case=$(echo $user_vnet_name | tr '[:upper:]' '[:lower:]')
stdouttmp=$(avn vpc peering-connection create --project $aiven_project_name --project-vpc-id $aiven_project_vpc_id --peer-cloud-account $user_subscription_id --peer-resource-group $user_resource_group_lower_case --peer-vpc $user_vnet_name_lower_case --peer-azure-app-id $user_app_id --peer-azure-tenant-id $user_tenant_id)
if test -z "$stdouttmp"
then
    echo "Failed to create Aiven VPC peering connection" >&2; exit 1
fi
echo $stdouttmp > step11_avn_vpc_peering_connection_create.json


########################################################################
printf '\n\n### Step 12\n'
echo "Waiting for VPC PENDING_PEER state..."
i=0
while true
do
    i=$(( (i+1) %4 ))
    stdouttmp=$(avn vpc peering-connection get -v --project $aiven_project_name --project-vpc-id $aiven_project_vpc_id --peer-cloud-account $user_subscription_id --peer-resource-group $user_resource_group_lower_case --peer-vpc $user_vnet_name_lower_case --json | jq -r '.state')
    printf "\r${SPIN_STRING:$i:1} $stdouttmp"
    if [ $stdouttmp == "PENDING_PEER" ]
    then
        break
    fi
    sleep 5
done
printf '\n'
stdouttmp=$(avn vpc peering-connection get -v --project $aiven_project_name --project-vpc-id $aiven_project_vpc_id --peer-cloud-account $user_subscription_id --peer-resource-group $user_resource_group_lower_case --peer-vpc $user_vnet_name_lower_case --json)
if test -n "$stdouttmp"
then
    echo $stdouttmp > step12_avn_vpc_peering_connection_get.json
fi
aiven_tenant_id=$(jq -r '.state_info ."to-tenant-id"' step12_avn_vpc_peering_connection_get.json)
if test -z "$aiven_tenant_id"
then
    echo "Invalid aiven_tenant_id" >&2; exit 1
fi
aiven_vnet_id=$(jq -r '.state_info ."to-network-id"' step12_avn_vpc_peering_connection_get.json)
if test -z "$aiven_vnet_id"
then
    echo "Invalid aiven_vnet_id" >&2; exit 1
fi
echo "aiven_tenant_id=$aiven_tenant_id"
echo "aiven_vnet_id=$aiven_vnet_id"
sleep 15

########################################################################
printf '\n\n### Step 13\n'
az account clear
echo 'log in app object to your AD tenant...'
stdouttmp=$(az login --service-principal -u $user_app_id -p $user_app_secret --tenant $user_tenant_id)
if test -z "$stdouttmp"
then
    echo "Failed to log in the application object" >&2; exit 1
fi
echo $stdouttmp > step13_1_az_login_1.json
echo 'log in app object to the Aiven AD tenant...'
stdouttmp=$(az login --service-principal -u $user_app_id -p "$user_app_secret" --tenant $aiven_tenant_id)
if test -z "$stdouttmp"
then
    echo "Failed to log in the application object to the Aiven AD tenant" >&2; exit 1
fi
echo $stdouttmp > step13_2_az_login_2.json
read -p "Enter peering name (vpc_peering_aiven): " peering_name
if test -z "$peering_name"
then
    peering_name="vpc_peering_aiven"
fi
stdouttmp=$(az network vnet peering create --name $peering_name --remote-vnet $aiven_vnet_id --vnet-name $user_vnet_name --resource-group $user_resource_group --subscription $user_subscription_id --allow-vnet-access)
if test -z "$stdouttmp"
then
    echo "Failed to create VNet peering" >&2; exit 1
fi
echo $stdouttmp > step13_3_network_vnet_peering_create.json
echo "VPC peering created."
echo "Waiting for VPC ACTIVE state..."
i=0
while true
do
    i=$(( (i+1) %4 ))
    stdouttmp=$(avn vpc peering-connection get -v --project $aiven_project_name --project-vpc-id $aiven_project_vpc_id --peer-cloud-account $user_subscription_id --peer-resource-group $user_resource_group_lower_case --peer-vpc $user_vnet_name_lower_case --json | jq -r '.state')
    printf "\r${SPIN_STRING:$i:1} $stdouttmp"
    if [ $stdouttmp == "ACTIVE" ]
    then
        break
    fi
    sleep 5
done
printf '\n'
az logout
az account clear
