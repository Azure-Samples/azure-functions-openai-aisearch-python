param principalID string
param principalType string = 'ServicePrincipal' // Workaround for https://learn.microsoft.com/en-us/azure/role-based-access-control/role-assignments-template#new-service-principal
param roleDefinitionIds array
param aiResourceName string

resource search 'Microsoft.Search/searchServices@2021-04-01-preview' existing = {
  name: aiResourceName
}

// Allow access from API to storage account using a managed identity and least priv Storage roles
resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = [for roleDefinitionId in roleDefinitionIds: {
  name: guid(search.id, principalID, roleDefinitionId)
  scope: search
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
    principalId: principalID
    principalType: principalType 
  }
}]
