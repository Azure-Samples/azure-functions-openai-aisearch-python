$ErrorActionPreference = "Stop"

$output = azd env get-values

# Parse the output to get the resource names and the resource group
foreach ($line in $output) {
    if ($line -match "AZURE_AISEARCH_NAME"){
        $AISearchResourceName = ($line -split "=")[1] -replace '"',''
    }
    if ($line -match "AZURE_OPENAI_NAME"){
        $OpenAIResourceName = ($line -split "=")[1] -replace '"',''
    }
    if ($line -match "RESOURCE_GROUP"){
        $ResourceGroup = ($line -split "=")[1] -replace '"',''
    }
}

# Read the config.json file to see if vnet is enabled
$ConfigFolder = ($ResourceGroup -split '-' | Select-Object -Skip 1) -join '-'
$jsonContent = Get-Content -Path ".azure\$ConfigFolder\config.json" -Raw | ConvertFrom-Json
if ($jsonContent.infra.parameters.skipVnet -eq $true) {
    Write-Output "VNet is not enabled. Skipping adding the client IP to the network rule of the Azure OpenAI and the Azure AI Search services"
}
else {
    Write-Output "VNet is enabled. Adding the client IP to the network rule of the Azure OpenAI and the Azure AI Search services"
    # Get the client IP
    $ClientIP = Invoke-RestMethod -Uri 'https://api.ipify.org'

    $Rules = az cognitiveservices account show  --resource-group $ResourceGroup --name $OpenAIResourceName --query "properties.networkAcls.ipRules"
    # Parse the JSON string to get the list of values in $rules
    $RulesList = $Rules | ConvertFrom-Json

    # Iterate through each rule 
    $IPExists = $false
    foreach ($Rule in $RulesList) {
        $IPExists = $Rule.value -contains $ClientIP
    }
    if ($false -eq $IPExists) {
        # Add the client IP to the network rule of the Azure Cognitive Services OpenAI account and mark the public network access as enabled
        Write-Output "Adding the client IP $ClientIP to the network rule of the Azure OpenAI service $OpenAIResourceName"
        az cognitiveservices account network-rule add --resource-group $ResourceGroup --name $OpenAIResourceName --ip-address $ClientIP > $null
        # Mark the public network access as enabled since the client IP is added to the network rule
        $OpenAIResourceId = az cognitiveservices account show --resource-group $ResourceGroup --name $OpenAIResourceName --query id
        az resource update  --ids $OpenAIResourceId --set properties.publicNetworkAccess="Enabled" > $null
    }
    else {
        Write-Output "The client IP $ClientIP is already in the network rule of the Azure OpenAI service $OpenAIResourceName"
    }


    $Rules = az search service show  --resource-group $ResourceGroup  --name $AISearchResourceName --query "networkRuleSet.ipRules"
    $RulesList = $Rules | ConvertFrom-Json

    $IPExists = $false
    foreach ($Rule in $RulesList) {
        $IPExists = $Rule.value -contains $ClientIP
    }
    if ($false -eq $IPExists) {
        # Add the client IP to the network rule of the Azure Cognitive Services Azure Cognitive Search account
        Write-Output "Adding the client IP $ClientIP to the network rule of the Azure AI Search service $AISearchResourceName"
        az search service update --resource-group $ResourceGroup  --name $AISearchResourceName --ip-rules $ClientIP > $null
        # Mark the public network access as enabled since the client IP is added to the network rule
        $OpenAIResourceId = az search service show --resource-group $ResourceGroup --name $AISearchResourceName --query id
        az resource update  --ids $OpenAIResourceId --set properties.publicNetworkAccess="Enabled" > $null
    }
    else {
        Write-Output "The client IP $ClientIP is already in the network rule of the Azure AI Search service $AISearchResourceName"
    }
}