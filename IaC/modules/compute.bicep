param location string = resourceGroup().location

param subnetDevId string
param subnetProdId string


@secure()
param adminPassword string

param adminUsername string = 'azureuser'

import {
  vmDevConfig
  vmProdConfig
} from '../variables.bicep'

import {
  devScriptUri
  prodScriptUri
} from '../variables.bicep'

//////////////////////////////////// VM DEV ////////////////////////////////////

module vmDev './vm.bicep' = {
  name: 'vmDevDeployment'

  params: {
    location: location
    config: vmDevConfig

    subnetId: subnetDevId

    adminUsername: adminUsername
    adminPassword: adminPassword

    customScriptUri: devScriptUri
    customScriptName: 'setup-dev.sh'
    extensionName: 'setup-dev'
  }
}

//////////////////////////////////// VM PROD ////////////////////////////////////

module vmProd './vm.bicep' = {
  name: 'vmProdDeployment'

  params: {
    location: location
    config: vmProdConfig

    subnetId: subnetProdId

    adminUsername: adminUsername
    adminPassword: adminPassword

    customScriptUri: prodScriptUri
    customScriptName: 'setup-prod.sh'
    extensionName: 'setup-prod'
  }
}
 
output vmDevId string = vmDev.outputs.vmId
output vmProdId string = vmProd.outputs.vmId
