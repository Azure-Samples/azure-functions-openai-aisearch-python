targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the the environment which is used to generate a short unique hash used in all resources.')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
@allowed(['australiaeast', 'eastasia', 'eastus', 'eastus2', 'northeurope', 'southcentralus', 'southeastasia', 'uksouth', 'westus2'])
@metadata({
  azd: {
    type: 'location'
  }
})
param location string
// If you want to skip the virtual network and private endpoint creation, set this to true
param skipVnet bool
param apiServiceName string = ''
param apiUserAssignedIdentityName string = ''
param applicationInsightsName string = ''
param appServicePlanName string = ''
param logAnalyticsName string = ''
param resourceGroupName string = ''
param storageAccountName string = ''
param vNetName string = ''
param disableLocalAuth bool = true
param openAiServiceName string = ''
param AISearchName string = ''
param AISearchSkuName object = {name: 'standard'}
param openAiSkuName string
@allowed([ 'azure', 'openai', 'azure_custom' ])
param openAiHost string // Set in main.parameters.json

param chatGptModelName string = ''
param chatGptDeploymentName string = ''
param chatGptDeploymentVersion string = ''
param chatGptDeploymentCapacity int = 0

var chatGpt = {
  modelName: !empty(chatGptModelName) ? chatGptModelName : startsWith(openAiHost, 'azure') ? 'gpt-4o' : 'gpt-4o'
  deploymentName: !empty(chatGptDeploymentName) ? chatGptDeploymentName : 'chat'
  deploymentVersion: !empty(chatGptDeploymentVersion) ? chatGptDeploymentVersion : '2024-08-06'
  deploymentCapacity: chatGptDeploymentCapacity != 0 ? chatGptDeploymentCapacity : 40
}

param embeddingModelName string = ''
param embeddingDeploymentName string = ''
param embeddingDeploymentVersion string = ''
param embeddingDeploymentCapacity int = 0
param embeddingDimensions int = 0
var embedding = {
  modelName: !empty(embeddingModelName) ? embeddingModelName : 'text-embedding-3-small'
  deploymentName: !empty(embeddingDeploymentName) ? embeddingDeploymentName : 'embeddings'
  deploymentVersion: !empty(embeddingDeploymentVersion) ? embeddingDeploymentVersion : '1'
  deploymentCapacity: embeddingDeploymentCapacity != 0 ? embeddingDeploymentCapacity : 220
  dimensions: embeddingDimensions != 0 ? embeddingDimensions : 1536
}

@description('Id of the user or app to assign application roles')
param principalId string = ''

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }
var functionAppName = !empty(apiServiceName) ? apiServiceName : '${abbrs.webSitesFunctions}api-${resourceToken}'
var deploymentStorageContainerName = 'app-package-${take(functionAppName, 32)}-${take(toLower(uniqueString(functionAppName, resourceToken)), 7)}'

// Organize resources in a resource group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: !empty(resourceGroupName) ? resourceGroupName : '${abbrs.resourcesResourceGroups}${environmentName}'
  location: location
  tags: tags
}

// User assigned managed identity to be used by the function app to reach storage
module apiUserAssignedIdentity './core/identity/userAssignedIdentity.bicep' = {
  name: 'apiUserAssignedIdentity'
  scope: rg
  params: {
    location: location
    tags: tags
    identityName: !empty(apiUserAssignedIdentityName) ? apiUserAssignedIdentityName : '${abbrs.managedIdentityUserAssignedIdentities}api-${resourceToken}'
  }
}

// The application backend is a function app
module appServicePlan './core/host/appserviceplan.bicep' = {
  name: 'appserviceplan'
  scope: rg
  params: {
    name: !empty(appServicePlanName) ? appServicePlanName : '${abbrs.webServerFarms}${resourceToken}'
    location: location
    tags: tags
    sku: {
      name: 'FC1'
      tier: 'FlexConsumption'
    }
  }
}

module api './app/api.bicep' = {
  name: 'api'
  scope: rg
  params: {
    name: functionAppName
    location: location
    tags: tags
    applicationInsightsName: monitoring.outputs.applicationInsightsName
    appServicePlanId: appServicePlan.outputs.id
    runtimeName: 'python'
    runtimeVersion: '3.11'
    storageAccountName: storage.outputs.name
    deploymentStorageContainerName: deploymentStorageContainerName
    identityId: apiUserAssignedIdentity.outputs.identityId
    identityClientId: apiUserAssignedIdentity.outputs.identityClientId
    appSettings: {
      CHAT_MODEL_DEPLOYMENT_NAME: chatGpt.deploymentName
      EMBEDDING_MODEL_DEPLOYMENT_NAME: embedding.deploymentName
    }
    virtualNetworkSubnetId: skipVnet ? '' : serviceVirtualNetwork.outputs.appSubnetID
    aiServiceUrl: ai.outputs.endpoint
    aiSearchUrl: aisearch.outputs.endpoint
  }
}

module ai 'core/ai/openai.bicep' = {
  name: 'openai'
  scope: rg
  params: {
    name: !empty(openAiServiceName) ? openAiServiceName : '${abbrs.cognitiveServicesAccounts}${resourceToken}'
    location: location
    tags: tags
    publicNetworkAccess: skipVnet == false ? 'Disabled' : 'Enabled'
    sku: {
      name: openAiSkuName
    }
    deployments: [
      {
        name: embedding.deploymentName
        capacity: embedding.deploymentCapacity
        model: {
          format: 'OpenAI'
          name: embedding.modelName
          version: embedding.deploymentVersion
        }
        scaleSettings: {
          scaleType: 'Standard'
        }
      }
      {
        name: chatGpt.deploymentName
        capacity: chatGpt.deploymentCapacity
        model: {
          format: 'OpenAI'
          name: chatGpt.modelName
          version: chatGpt.deploymentVersion
        }
        scaleSettings: {
          scaleType: 'Standard'
        }
      }
    ]
  }
}

module aisearch 'core/aisearch/aisearch.bicep' = {
  name: 'aisearch'
  scope: rg
  params: {
    name: !empty(AISearchName) ? AISearchName : '${abbrs.searchSearchServices}${resourceToken}'
    location: location
    tags: tags
    publicNetworkAccess: skipVnet == false ? 'Disabled' : 'Enabled'
    sku: AISearchSkuName
  }
}

// Backing storage for Azure functions backend processor
module storage 'core/storage/storage-account.bicep' = {
  name: 'storage'
  scope: rg
  params: {
    name: !empty(storageAccountName) ? storageAccountName : '${abbrs.storageStorageAccounts}${resourceToken}'
    location: location
    tags: tags
    containers: [
      {name: deploymentStorageContainerName}
     ]
     networkAcls: skipVnet ? {} : {
        defaultAction: 'Deny'
      }
  }
}

var storageRoleDefinitionId  = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b' // Storage Blob Data Owner role

// Allow access from api to storage account using a managed identity
module storageRoleAssignmentApi 'core/storage/storage-Access.bicep' = {
  name: 'storageRoleAssignmentapi'
  scope: rg
  params: {
    storageAccountName: storage.outputs.name
    roleDefinitionID: storageRoleDefinitionId
    principalID: apiUserAssignedIdentity.outputs.identityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

module storageRoleAssignmentUserIdentityApi 'core/storage/storage-Access.bicep' = {
  name: 'storageRoleAssignmentUserIdentityApi'
  scope: rg
  params: {
    storageAccountName: storage.outputs.name
    roleDefinitionID: storageRoleDefinitionId
    principalID: principalId
    principalType: 'User'
  }
}

var storageQueueDataContributorRoleDefinitionId  = '974c5e8b-45b9-4653-ba55-5f855dd0fb88' // Storage Queue Data Contributor

module storageQueueDataContributorRoleAssignmentprocessor 'core/storage/storage-Access.bicep' = {
  name: 'storageQueueDataContributorRoleAssignmentprocessor'
  scope: rg
  params: {
    storageAccountName: storage.outputs.name
    roleDefinitionID: storageQueueDataContributorRoleDefinitionId
    principalID: apiUserAssignedIdentity.outputs.identityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

module storageQueueDataContributorRoleAssignmentUserIdentityprocessor 'core/storage/storage-Access.bicep' = {
  name: 'storageQueueDataContributorRoleAssignmentUserIdentityprocessor'
  scope: rg
  params: {
    storageAccountName: storage.outputs.name
    roleDefinitionID: storageQueueDataContributorRoleDefinitionId
    principalID: principalId
    principalType: 'User'
  }
}

var storageTableDataContributorRoleDefinitionId  = '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3' // Storage Table Data Contributor

module storageTableDataContributorRoleAssignmentprocessor 'core/storage/storage-Access.bicep' = {
  name: 'storageTableDataContributorRoleAssignmentprocessor'
  scope: rg
  params: {
    storageAccountName: storage.outputs.name
    roleDefinitionID: storageTableDataContributorRoleDefinitionId
    principalID: apiUserAssignedIdentity.outputs.identityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

module storageTableDataContributorRoleAssignmentUserIdentityprocessor 'core/storage/storage-Access.bicep' = {
  name: 'storageTableDataContributorRoleAssignmentUserIdentityprocessor'
  scope: rg
  params: {
    storageAccountName: storage.outputs.name
    roleDefinitionID: storageTableDataContributorRoleDefinitionId
    principalID: principalId
    principalType: 'User'
  }
}

var cogRoleDefinitionId  = 'a97b65f3-24c7-4388-baec-2e87135dc908' // Cognitive Services User

// Allow access from api to storage account using a managed identity
module cogRoleAssignmentApi 'core/ai/openai-access.bicep' = {
  name: 'cogRoleAssignmentapi'
  scope: rg
  params: {
    aiResourceName: ai.outputs.name
    roleDefinitionID: cogRoleDefinitionId
    principalID: apiUserAssignedIdentity.outputs.identityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

module cogRoleAssignmentUserIdentityApi 'core/ai/openai-access.bicep' = {
  name: 'cogRoleAssignmentUserIdentityApi'
  scope: rg
  params: {
    aiResourceName: ai.outputs.name
    roleDefinitionID: cogRoleDefinitionId
    principalID: principalId
    principalType: 'User'
  }
}

var SearchRoleDefinitionIds = ['8ebe5a00-799e-43f5-93ac-243d3dce84a7'  // Azure Search Index Data Contributor
                               '7ca78c08-252a-4471-8644-bb5ff32d4ba0'  // Azure Search Service Contributor (required if index is not yet created)
                              ]

// Allow access from api to storage account using a managed identity
module searchRoleAssignmentApi 'core/aisearch/aisearch-access.bicep' = {
  name: 'searchRoleAssignmentapi'
  scope: rg
  params: {
    aiResourceName: aisearch.outputs.name
    roleDefinitionIds: SearchRoleDefinitionIds
    principalID: apiUserAssignedIdentity.outputs.identityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

module searchRoleAssignmentUserIdentityApi 'core/aisearch/aisearch-access.bicep' = {
  name: 'searchRoleAssignmentUserIdentityApi'
  scope: rg
  params: {
    aiResourceName: aisearch.outputs.name
    roleDefinitionIds: SearchRoleDefinitionIds
    principalID: principalId
    principalType: 'User'
  }
}

// Virtual Network & private endpoint to blob storage
module serviceVirtualNetwork 'app/vnet.bicep' =  if (!skipVnet) {
  name: 'serviceVirtualNetwork'
  scope: rg
  params: {
    location: location
    tags: tags
    vNetName: !empty(vNetName) ? vNetName : '${abbrs.networkVirtualNetworks}${resourceToken}'
  }
}

module storagePrivateEndpoint 'core/storage/storage-PrivateEndpoint.bicep' = if (!skipVnet) {
  name: 'storageServicePrivateEndpoint'
  scope: rg
  params: {
    location: location
    tags: tags
    virtualNetworkName: !empty(vNetName) ? vNetName : '${abbrs.networkVirtualNetworks}${resourceToken}'
    subnetName: skipVnet ? '' : serviceVirtualNetwork.outputs.peSubnetName
    resourceName: storage.outputs.name
  }
}

module openaiPrivateEndpoint 'core/ai/openai-privateendpoint.bicep' = if (!skipVnet) {
  name: 'openaiServicePrivateEndpoint'
  scope: rg
  params: {
    location: location
    tags: tags
    virtualNetworkName: !empty(vNetName) ? vNetName : '${abbrs.networkVirtualNetworks}${resourceToken}'
    subnetName: skipVnet ? '' : serviceVirtualNetwork.outputs.peSubnetName
    resourceName: ai.outputs.name
  }
}

module aisearchPrivateEndpoint 'core/aisearch/aisearch-privateendpoint.bicep' = if (!skipVnet) {
  name: 'aisearchServicePrivateEndpoint'
  scope: rg
  params: {
    location: location
    tags: tags
    virtualNetworkName: !empty(vNetName) ? vNetName : '${abbrs.networkVirtualNetworks}${resourceToken}'
    subnetName: skipVnet ? '' : serviceVirtualNetwork.outputs.peSubnetName
    resourceName: aisearch.outputs.name
  }
}

// Monitor application with Azure Monitor
module monitoring './core/monitor/monitoring.bicep' = {
  name: 'monitoring'
  scope: rg
  params: {
    location: location
    tags: tags
    logAnalyticsName: !empty(logAnalyticsName) ? logAnalyticsName : '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    applicationInsightsName: !empty(applicationInsightsName) ? applicationInsightsName : '${abbrs.insightsComponents}${resourceToken}'
    disableLocalAuth: disableLocalAuth  
  }
}

var monitoringRoleDefinitionId = '3913510d-42f4-4e42-8a64-420c390055eb' // Monitoring Metrics Publisher role ID

// Allow access from api to application insights using a managed identity
module appInsightsRoleAssignmentApi './core/monitor/appinsights-access.bicep' = {
  name: 'appInsightsRoleAssignmentapi'
  scope: rg
  params: {
    appInsightsName: monitoring.outputs.applicationInsightsName
    roleDefinitionID: monitoringRoleDefinitionId
    principalID: apiUserAssignedIdentity.outputs.identityPrincipalId
  }
}

// App outputs
output APPLICATIONINSIGHTS_CONNECTION_STRING string = monitoring.outputs.applicationInsightsConnectionString
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output SERVICE_API_NAME string = api.outputs.SERVICE_API_NAME
output SERVICE_API_URI string = api.outputs.SERVICE_API_URI
output AZURE_FUNCTION_APP_NAME string = api.outputs.SERVICE_API_NAME
output AZURE_OPENAI_NAME string = ai.outputs.name
output AZURE_AISEARCH_NAME string = aisearch.outputs.name
output RESOURCE_GROUP string = rg.name
output AZURE_OPENAI_ENDPOINT string = ai.outputs.endpoint
output AZURE_AISEARCH_ENDPOINT string = aisearch.outputs.endpoint
