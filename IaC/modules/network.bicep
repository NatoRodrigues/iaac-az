param location string = resourceGroup().location

//////////////////////////////////// VNET DEV ////////////////////////////////////

resource vnet_dev 'Microsoft.Network/virtualNetworks@2023-02-01' = {
  name: 'vnet-dev'
  location: location

  tags: {
    Environment: 'Dev'
    Owner: 'Renato'
    Project: 'ops-toolkit'
    CostCenter: 'DEV001'
    CreatedBy: 'Bicep'
  }

  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }

    subnets: [
      {
        name: 'subnet-dev'

        properties: {
          networkSecurityGroup: {
            id: nsgDev.id
          }
          addressPrefix: '10.0.1.0/24'
        }
      }
    ]
  }
}

//////////////////////////////////// VNET PROD ////////////////////////////////////

resource vnet_prod 'Microsoft.Network/virtualNetworks@2023-02-01' = {
  name: 'vnet-prod'
  location: location

  tags: {
    Environment: 'Prod'
    Owner: 'Renato'
    Project: 'ops-toolkit'
    CostCenter: 'PROD001'
    CreatedBy: 'Bicep'
  }

  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.1.0.0/16'
      ]
    }

    subnets: [
      {
        name: 'subnet-prod'
        properties: {
          networkSecurityGroup: {
            id: nsgProd.id
          }
          addressPrefix: '10.1.1.0/24'
        }
      }
    ]
  }
}

//////////////////////////////////// NSG DEV ////////////////////////////////////

resource nsgDev 'Microsoft.Network/networkSecurityGroups@2023-02-01' = {
  name: 'nsg-dev'
  location: location

  tags: {
    Environment: 'Dev'
    Owner: 'Renato'
    Project: 'ops-toolkit'
    CostCenter: 'DEV001'
    CreatedBy: 'Bicep'
  }

  properties: {
    securityRules: [
      {
        name: 'AllowSSH'

        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
    ]
  }
}

//////////////////////////////////// NSG PROD ////////////////////////////////////

resource nsgProd 'Microsoft.Network/networkSecurityGroups@2023-02-01' = {
  name: 'nsg-prod'
  location: location

  tags: {
    Environment: 'Prod'
    Owner: 'Renato'
    Project: 'ops-toolkit'
    CostCenter: 'PROD001'
    CreatedBy: 'Bicep'
  }

  properties: {
    securityRules: [
      {
        name: 'AllowHTTP'

        properties: {
          priority: 100
          access: 'Allow'
          direction: 'Inbound'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '80'
        }
      }
    ]
  }
}


//////////////////////////////////// VNET PEERING ////////////////////////////////////

resource vnet_DevToVnet_Prod 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-02-01' = {
  name: 'vnet-dev-to-vnet-prod'
  parent: vnet_dev

  properties: {
    remoteVirtualNetwork: {
      id: vnet_prod.id
    }

    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

resource vnet_ProdToVnet_Dev 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-02-01' = {
  name: 'vnet-prod-to-vnet-dev'
  parent: vnet_prod

  properties: {
    remoteVirtualNetwork: {
      id: vnet_dev.id
    }

    allowVirtualNetworkAccess: true
    allowForwardedTraffic: false
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

//////////////////////////////////// OUTPUTS ////////////////////////////////////

output subnetDevId string = vnet_dev.properties.subnets[0].id
output subnetProdId string = vnet_prod.properties.subnets[0].id
 
