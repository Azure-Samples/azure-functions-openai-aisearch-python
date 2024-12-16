#!/bin/bash
set -e

output=$(azd env get-values)

# Parse the output to get the resource names and the resource group
while IFS= read -r line; do
    if [[ $line == AZURE_AISEARCH_NAME* ]]; then
        AISearchResourceName=$(echo "$line" | cut -d'=' -f2 | tr -d '"')
    elif [[ $line == AZURE_OPENAI_NAME* ]]; then
        OpenAIResourceName=$(echo "$line" | cut -d'=' -f2 | tr -d '"')
    elif [[ $line == RESOURCE_GROUP* ]]; then
        ResourceGroup=$(echo "$line" | cut -d'=' -f2 | tr -d '"')
    fi
done <<< "$output"

# Read the config.json file to see if vnet is enabled
ConfigFolder=$(echo "$ResourceGroup" | cut -d'-' -f2-)
configFile=".azure/$ConfigFolder/config.json"

if [[ -f "$configFile" ]]; then
    jsonContent=$(cat "$configFile")
    skipVnet=$(echo "$jsonContent" | grep '"skipVnet"' | sed 's/.*"skipVnet":\s*"\([^"]*\)".*/\1/')
else
    echo "Config file $configFile not found. Assuming VNet is enabled."
    skipVnet="false"
fi

# skipVnet is in the form "skipVnet": false
if echo "$skipVnet" | grep -iq "true"; then
    echo "VNet is not enabled. Skipping adding the client IP to the network rule of the Azure OpenAI and the Azure AI Search services"
else
    echo "VNet is enabled. Adding the client IP to the network rule of the Azure OpenAI and the Azure AI Search services"
    
    # Get the client IP
    ClientIP=$(curl -s https://api.ipify.org)

    Rules=$(az cognitiveservices account show --resource-group "$ResourceGroup" --name "$OpenAIResourceName" --query "properties.networkAcls.ipRules" -o tsv)
    IPExists=$(echo "$Rules" | grep -q "$ClientIP" && echo "true" || echo "false")

    if [[ $IPExists == "false" ]]; then
        echo "Adding the client IP $ClientIP to the network rule of the Azure OpenAI service $OpenAIResourceName"
        az cognitiveservices account network-rule add --resource-group "$ResourceGroup" --name "$OpenAIResourceName" --ip-address "$ClientIP" > /dev/null
        OpenAIResourceId=$(az cognitiveservices account show --resource-group "$ResourceGroup" --name "$OpenAIResourceName" --query id -o tsv)
        MSYS_NO_PATHCONV=1 az resource update --ids "$OpenAIResourceId" --set properties.publicNetworkAccess="Enabled" > /dev/null
    else
        echo "The client IP $ClientIP is already in the network rule of the Azure OpenAI service $OpenAIResourceName"
    fi

    Rules=$(az search service show --resource-group "$ResourceGroup" --name "$AISearchResourceName" --query "networkRuleSet.ipRules")
    IPExists=$(echo "$Rules" | grep -q "$ClientIP" && echo "true" || echo "false")

    if [[ $IPExists == "false" ]]; then
        echo "Adding the client IP $ClientIP to the network rule of the Azure AI Search service $AISearchResourceName"
        az search service update --resource-group "$ResourceGroup" --name "$AISearchResourceName" --ip-rules "$ClientIP" > /dev/null
        AISearchResourceId=$(az search service show --resource-group "$ResourceGroup" --name "$AISearchResourceName" --query id -o tsv)
        MSYS_NO_PATHCONV=1 az resource update --ids "$AISearchResourceId" --set properties.publicNetworkAccess="Enabled" > /dev/null
    else
        echo "The client IP $ClientIP is already in the network rule of the Azure AI Search service $AISearchResourceName"
    fi
fi
