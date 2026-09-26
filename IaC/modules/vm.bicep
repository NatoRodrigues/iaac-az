param location string
param config {
  name: string
  computerName: string
  nicName: string
  osDiskName: string
  environment: string
  costCenter: string
  autoShutdown: string
  backupRequired: string
  criticality: string
}

param subnetId string
 
param customScriptUri string
param customScriptName string
param extensionName string

@secure()
param adminPassword string

param adminUsername string = 'azureuser'

var resourceTags = {
  Environment: config.environment
  Owner: 'Renato'
  Project: 'ops-toolkit'
  CostCenter: config.costCenter
  AutoShutDown: config.autoShutdown
  BackupRequired: config.backupRequired
  Criticality: config.criticality
  Monitoring: 'Enabled'
  DataClassification: 'Internal'
  CreatedBy: 'Bicep'
}

//////////////////////////////////// NIC ////////////////////////////////////

resource nic 'Microsoft.Network/networkInterfaces@2023-02-01' = {
  name: config.nicName
  location: location
  tags: resourceTags

  properties: {

    ipConfigurations: [
      {
        name: 'ipconfig1'
        
        properties: {
          subnet: {
            id: subnetId
          }

          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

//////////////////////////////////// VM ////////////////////////////////////

resource vm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: config.name
  location: location
  tags: resourceTags

  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }

    osProfile: {
      computerName: config.computerName
      adminUsername: adminUsername
      adminPassword: adminPassword
    }

    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id

          properties: {
            primary: true
          }
        }
      ]
    }

    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }

      osDisk: {
        name: config.osDiskName
        createOption: 'FromImage'

        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
  }
}

//////////////////////////////////// CUSTOM SCRIPT ////////////////////////////////////

resource setup 'Microsoft.Compute/virtualMachines/extensions@2023-03-01' = {
  parent: vm
  name: extensionName
  location: location

  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true

    settings: {
      fileUris: [
        customScriptUri
      ]

      commandToExecute: 'bash ${customScriptName}'
    }
  }
}

//////////////////////////////////// OUTPUTS ////////////////////////////////////

output vmId string = vm.id
output vmName string = vm.name
output nicId string = nic.id
