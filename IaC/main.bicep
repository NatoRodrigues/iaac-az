@description('Email that receives Azure Monitor alerts.')
param alertEmail string

@secure()

param adminPassword string
param adminUsername string = 'azureuser'
 
 
targetScope = 'resourceGroup'

param location string = resourceGroup().location


module network './modules/network.bicep' = {
  name: 'networkDeployment'
  params: {
    location: location
  }
}

module compute './modules/compute.bicep' = {
  name: 'computeDeployment'

  params: {
    location: location

    adminUsername: adminUsername
    adminPassword: adminPassword

    subnetDevId: network.outputs.subnetDevId
    subnetProdId: network.outputs.subnetProdId
  }
}

module storage './modules/storage.bicep' = {
  name: 'storageDeployment'
  params: {
    location: location
  }
}

module orphans './modules/orphans.bicep' = {
  name: 'orphansDeployment'
  params: {
    location: location
  }
}

 module monitoring './modules/monitoring.bicep' = {
  name: 'monitoringDeployment'

  params: {
    location: location

    vmDevId: compute.outputs.vmDevId
    vmProdId: compute.outputs.vmProdId

    alertEmail: alertEmail
    cpuThreshold: 5
    alertWindowSize: 'PT1H'
    evaluationFrequency: 'PT15M'
  }
}
