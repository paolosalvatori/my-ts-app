#!/bin/bash

# For more info, read https://purple.telstra.com/blog/host-your-static-website-in-azure-storage-using-azure-cli

#Variables
cdnProfileName="babocdn"
resourceGroupName="CdnRG"
location="WestEurope"
sku="Standard_Microsoft"
cdnEndpointName="babo"
storageAccountName="baboweb"
storageAccountResourceGroupName="StorageAccountsRG"
dnsZoneName="babosbird.com"
dnsZoneResourceGroupName="DnsResourceGroup"
dnsSubdomain="static"
cdnRuleName="enforceHttps"
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

# Create CDN
echo "Checking if [$cdnProfileName] CDN profile actually exists in the [$subscriptionName] subscription..."
az cdn profile show --name $cdnProfileName --resource-group $resourceGroupName &>/dev/null

if [[ $? != 0 ]]; then
    echo "No [$cdnProfileName] CDN profile actually exists in the [$subscriptionName] subscription"
    echo "Creating [$cdnProfileName] CDN profile in the [$subscriptionName] subscription..."

    az cdn profile create \
        --name $cdnProfileName \
        --resource-group $resourceGroupName \
        --location $location \
        --sku $sku 1>/dev/null

    if [[ $? == 0 ]]; then
        echo "[$cdnProfileName] CDN profile successfully created in the [$subscriptionName] subscription"
    else
        echo "Failed to create [$cdnProfileName] CDN profile in the [$subscriptionName] subscription"
        exit
    fi
else
    echo "[$cdnProfileName] CDN profile already exists in the [$subscriptionName] subscription"
fi

# Retrieve the URL of the static website
staticWebsiteUrl=$(
    az storage account show \
        --name $storageAccountName \
        --resource-group $storageAccountResourceGroupName \
        --query "primaryEndpoints.web" \
        --output tsv
)

if [[ -n $staticWebsiteUrl ]]; then
    echo "[$staticWebsiteUrl] is the URL of the static website in the [$storageAccountName] storage account"
else
    echo "Failed to retrieve the URL of the static website in the [$storageAccountName] storage account"
    exit -1
fi

staticWebsiteHostname=$(echo $staticWebsiteUrl | awk -F[/:] '{print $4}')
echo "[$staticWebsiteHostname] is the hostname of the static website in the [$storageAccountName] storage account"

# Create the CDN endpoint
echo "Checking if [$cdnEndpointName] CDN endpoint actually exists in the [$cdnProfileName] CDN profile..."
az cdn endpoint show \
    --name $cdnEndpointName \
    --profile-name $cdnProfileName \
    --resource-group $resourceGroupName &>/dev/null

if [[ $? != 0 ]]; then
    echo "No [$cdnEndpointName] CDN endpoint actually exists in the [$cdnProfileName] CDN profile"
    echo "Creating [$cdnEndpointName] CDN endpoint in the [$cdnProfileName] CDN profile..."

    cdnEndpointHostname=$(az cdn endpoint create \
        --name $cdnEndpointName \
        --profile-name $cdnProfileName \
        --resource-group $resourceGroupName \
        --enable-compression \
        --location $location \
        --origin $staticWebsiteHostname \
        --origin-host-header $staticWebsiteHostname \
        --query hostName \
        --output tsv)

    if [[ -n $cdnEndpointHostname ]]; then
        echo "[$cdnEndpointName] CDN endpoint successfully created in the [$cdnProfileName] CDN profile"
    else
        echo "Failed to create [$cdnEndpointName] CDN endpoint in the [$cdnProfileName] CDN profile"
        exit
    fi
else
    echo "[$cdnEndpointName] CDN endpoint already exists in the [$cdnProfileName] CDN profile"
    cdnEndpointHostname=$(az cdn endpoint show \
        --name $cdnEndpointName \
        --profile-name $cdnProfileName \
        --resource-group $resourceGroupName \
        --query hostName \
        --output tsv)
fi

# Print the CDN endpoint URL
if [[ -n $cdnEndpointHostname ]]; then
    echo "[$cdnEndpointHostname] is the hostname of the [$cdnEndpointName] CDN endpoint"
else
    echo "Failed to retrieve the hostname of the [$cdnEndpointName] CDN endpoint"
    exit -1
fi

cdnEndpointUrl="https://${cdnEndpointHostname}/"
echo "[$cdnEndpointUrl] is the URL of the [$cdnEndpointName] CDN endpoint"

# Create a CNAME in the public DNS Zone
cname=$(az network dns record-set cname list \
    --zone-name $dnsZoneName \
    --resource-group $dnsZoneResourceGroupName \
    --query "[?name=='$dnsSubdomain'].name" \
    --output tsv)

if [[ -z $cname ]]; then
    echo "No CNAME record exists in [$dnsZoneName] DNS zone for the [$dnsSubdomain] subdomain"
    echo "Creating a CNAME record in [$dnsZoneName] DNS zone for the [$dnsSubdomain] subdomain with [$cdnEndpointHostname] as a value..."

    az network dns record-set cname set-record \
        --zone-name $dnsZoneName \
        --resource-group $dnsZoneResourceGroupName \
        --record-set-name $dnsSubdomain \
        --cname $cdnEndpointHostname 1>/dev/null

    if [[ $? == 0 ]]; then
        echo "CNAME record for the [$dnsSubdomain] subdomain successfully created in [$dnsZoneName] DNS zone"
    else
        echo "Failed to create an CNAME record for the [$dnsSubdomain] subdomain in [$dnsZoneName] DNS zone"
        exit -1
    fi
else
    echo "A CNAME record already exists in [$dnsZoneName] DNS zone for the [$dnsSubdomain] subdomain"
fi

# Add a custom domain to the CDN
echo "Checking if the [$dnsSubdomain] custom domain was already added to the [$cdnEndpointName] endpoint of the [$cdnProfileName] CDN profile..."
az cdn custom-domain show \
    --endpoint-name $cdnEndpointName \
    --profile-name $cdnProfileName \
    --resource-group $resourceGroupName \
    --name $dnsSubdomain &>/dev/null

if [[ $? != 0 ]]; then
    echo "[$dnsSubdomain] custom domain was not added yet to the [$cdnEndpointName] endpoint of the [$cdnProfileName] CDN profile"
    echo "Adding [$dnsSubdomain] custom domain to the [$cdnEndpointName] endpoint of the [$cdnProfileName] CDN profile..."

    az cdn custom-domain create \
        --endpoint-name $cdnEndpointName \
        --profile-name $cdnProfileName \
        --resource-group $resourceGroupName \
        --name $dnsSubdomain \
        --hostname "${dnsSubdomain}.${dnsZoneName}" 1>/dev/null

    if [[ $? == 0 ]]; then
        echo "[$dnsSubdomain] custom domain successfully added to the [$cdnEndpointName] endpoint of the [$cdnProfileName] CDN profile"
    else
        echo "Failed to add [$dnsSubdomain] custom domain to the [$cdnEndpointName] endpoint of the [$cdnProfileName] CDN profile"
        exit -1
    fi
else
    echo "[$dnsSubdomain] custom domain was already added to the [$cdnEndpointName] endpoint of the [$cdnProfileName] CDN profile"
fi

# Enable HTTPS on the custom domain
echo "Checking if HTTPS support is enabled on the [$dnsSubdomain] custom domain of the [$cdnEndpointName] CDN endpoint of the [$cdnProfileName] DNS profile..."
customHttpsProvisioningState=$(az cdn custom-domain show \
    --endpoint-name $cdnEndpointName \
    --profile-name $cdnProfileName \
    --resource-group $resourceGroupName \
    --name $dnsSubdomain \
    --query customHttpsProvisioningState \
    --output tsv)

if [[ $customHttpsProvisioningState == 'Disabled' ]]; then
    echo "Enabling HTTPS support for the [$dnsSubdomain] custom domain of the [$cdnEndpointName] CDN endpoint of the [$cdnProfileName] DNS profile..."

    az cdn custom-domain enable-https \
        --endpoint-name $cdnEndpointName \
        --profile-name $cdnProfileName \
        --resource-group $resourceGroupName \
        --name $dnsSubdomain &>/dev/null

    if [[ $? == 0 ]]; then
        echo "HTTPS support successfully enabled for the [$dnsSubdomain] custom domain of the [$cdnEndpointName] CDN endpoint of the [$cdnProfileName] DNS profile"
    else
        echo "Failed to enable HTTPS support for the [$dnsSubdomain] custom domain of the [$cdnEndpointName] CDN endpoint of the [$cdnProfileName] DNS profile"
        exit -1
    fi
else
    echo "HTTPS support is already enabled for the [$dnsSubdomain] custom domain of the [$cdnEndpointName] CDN endpoint of the [$cdnProfileName] DNS profile"
fi

# Rewrite HTTP requests to HTTPS
echo "Checking if the [$cdnRuleName] rule  was already added to the [$cdnEndpointName] endpoint of the [$cdnProfileName] CDN profile..."
ruleName=$(az cdn endpoint rule show \
    --name $cdnEndpointName \
    --profile-name $cdnProfileName \
    --resource-group $resourceGroupName \
    --query "deliveryPolicy.rules[?name=='$cdnRuleName'].name" \
    --output tsv)

if [[ -z $ruleName ]]; then
    echo "No [$cdnRuleName] rule exists for the [$cdnEndpointName] endpoint of the [$cdnProfileName] CDN profile"
    echo "Adding the [$cdnRuleName] rule to the [$cdnEndpointName] endpoint of the [$cdnProfileName] CDN profile..."
    az cdn endpoint rule add \
        --name $cdnEndpointName \
        --profile-name $cdnProfileName \
        --rule-name $cdnRuleName \
        --resource-group $resourceGroupName \
        --order 1 \
        --match-variable RequestScheme \
        --operator Equal \
        --match-values HTTP \
        --action-name UrlRedirect \
        --redirect-protocol Https \
        --redirect-type Moved &>/dev/null

    if [[ $? == 0 ]]; then
        echo "[$cdnRuleName] rule successfully added to the [$cdnEndpointName] endpoint of the [$cdnProfileName] CDN profile"
    else
        echo "Failed to add [$cdnRuleName] rule to the [$cdnEndpointName] endpoint of the [$cdnProfileName] CDN profile"
        exit -1
    fi
else
    echo "[$cdnRuleName] rule  was already added to the [$cdnEndpointName] endpoint of the [$cdnProfileName] CDN profile"
fi
