#!/bin/bash

#Variables
resourceGroupName="StorageAccountsRG"
storageAccountName="baboweb"
location="WestEurope"
sku="Standard_LRS"
servicePrincipalName="BaboStaticWebApp"
servicePrincipalRole="contributor"
tenantId=$(az account show --query tenantId --output tsv)
subscriptionId=$(az account show --query id --output tsv)
subscriptionName=$(az account show --query name --output tsv)

# Create resource group
echo "Checking if [$resourceGroupName] resource group actually exists in the [$subscriptionName] subscription..."
az group show --name $resourceGroupName &>/dev/null

if [[ $? != 0 ]]; then
    echo "No [$resourceGroupName] resource group actually exists in the [$subscriptionName] subscription"
    echo "Creating [$resourceGroupName] resource group in the [$subscriptionName] subscription..."

    # Create the resource group
    az group create \
    --name $resourceGroupName \
    --location $location 1>/dev/null

    if [[ $? == 0 ]]; then
        echo "[$resourceGroupName] resource group successfully created in the [$subscriptionName] subscription"
    else
        echo "Failed to create [$resourceGroupName] resource group in the [$subscriptionName] subscription"
        exit
    fi
else
    echo "[$resourceGroupName] resource group already exists in the [$subscriptionName] subscription"
fi

# Create storage account
echo "Checking if [$storageAccountName] storage account actually exists in the [$subscriptionName] subscription..."
az storage account show --name $storageAccountName &>/dev/null

if [[ $? != 0 ]]; then
    echo "No [$storageAccountName] storage account actually exists in the [$subscriptionName] subscription"
    echo "Creating [$storageAccountName] storage account in the [$subscriptionName] subscription..."

    az storage account create \
    --resource-group $resourceGroupName \
    --name $storageAccountName \
    --sku $sku \
    --encryption-services blob 1>/dev/null

    # Create the storage account
    if [[ $? == 0 ]]; then
        echo "[$storageAccountName] storage account successfully created in the [$subscriptionName] subscription"
    else
        echo "Failed to create [$storageAccountName] storage account in the [$subscriptionName] subscription"
        exit
    fi
else
    echo "[$storageAccountName] storage account already exists in the [$subscriptionName] subscription"
fi

# Get storage account key
echo "Retrieving the primary key of the [$storageAccountName] storage account..."
storageAccountKey=$(az storage account keys list --resource-group $resourceGroupName --account-name $storageAccountName --query [0].value -o tsv)

if [[ -n $storageAccountKey ]]; then
    echo "Primary key of the [$storageAccountName] storage account successfully retrieved"
else
    echo "Failed to retrieve the primary key of the [$storageAccountName] storage account"
    exit
fi

# Enable the static web site on the storage account
echo "Enabling the static web site on the [$storageAccountName] storage account..."
az storage blob service-properties update \
--account-name $storageAccountName \
--account-key $storageAccountKey \
--static-website true \
--404-document error.html \
--index-document index.html 1>/dev/null

if [[ $? == 0 ]]; then
    echo "Static web site successfully enabled on the [$storageAccountName] storage account"
else
    echo "Failed to enable static web site on the [$storageAccountName] storage account"
fi

# Print data
echo "----------------------------------------------------------------------------------------------"
echo "storageAccountName: $storageAccountName"
echo "access_key: $storageAccountKey"
echo "----------------------------------------------------------------------------------------------"

# Create service principal with contributor role
echo "Checking if [$servicePrincipalName] service principal already exists in the [$tenantId] tenant..."
displayName=$(
    az ad sp list \
    --display-name $servicePrincipalName \
    --query [].displayName \
    --output tsv
)

if [[ -z $displayName ]]; then
    echo "No [$servicePrincipalName] service principal already exists in the [$tenantId] tenant"
    echo "Creating [$servicePrincipalName] service principal in the [$tenantId] tenant..."

    az ad sp create-for-rbac \
    --name $servicePrincipalName \
    --role $servicePrincipalRole \
    --scopes /subscriptions/$subscriptionId/resourceGroups/$resourceGroupName 

    if [[ $? == 0 ]]; then
        echo "Static web site successfully enabled on the [$storageAccountName] storage account"
    else
        echo "Failed to to create [$servicePrincipalName] service principal in the [$tenantId] tenant"
    fi
else
    echo "[$servicePrincipalName] service principal already exists in the [$tenantId] tenant"
fi
