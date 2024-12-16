// Parameters
@description('Specifies the name of the virtual network.')
param virtualNetworkName string

@description('Specifies the name of the subnet.')
param subnetName string

@description('Specifies the resource with an endpoint.')
param resourceName string

@description('Specifies the location.')
param location string = resourceGroup().location

param tags object = {}

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2021-08-01' existing = {
  name: virtualNetworkName
}

resource search 'Microsoft.Search/searchServices@2021-04-01-preview' existing = {
  name: resourceName
}

var aiSearchPrivateDNSZoneName = 'privatelink.search.windows.net'

// Private DNS Zones
resource aisearchPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: aiSearchPrivateDNSZoneName
  location: 'global'
  tags: tags
  properties: {}
  dependsOn: [
    vnet
  ]
}

// Virtual Network Links
resource aisearchPrivateDnsZoneVirtualNetworkLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: aisearchPrivateDnsZone
  name: 'privatelink-link.search.windows.net'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

// Private Endpoints
resource aisearchPrivateEndpoint 'Microsoft.Network/privateEndpoints@2021-08-01' = {
  name: 'aisearch-private-endpoint'
  location: location
  tags: tags
  properties: {
    privateLinkServiceConnections: [
      {
        name: 'aisearchPrivateLinkConnection'
        properties: {
          privateLinkServiceId: search.id
          groupIds: [
            'searchService'
          ]
        }
      }
    ]
    subnet: {
      id: '${vnet.id}/subnets/${subnetName}'
    }
  }
}

resource aisearchPrivateDnsZoneGroupName 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-01-01' = {
  parent: aisearchPrivateEndpoint
  name: 'aisearchPrivateDnsZoneGroup'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'aisearchRecord'
        properties: {
          privateDnsZoneId: aisearchPrivateDnsZone.id
        }
      }
    ]
  }
}
