param location string = resourceGroup().location

//////////////////////////////////// PUBLIC IP ORPHAN ////////////////////////////////////
resource publicIpOrphan 'Microsoft.Network/publicIPAddresses@2023-02-01' = {
  name: 'pip-orphan'
  location: location

  tags: {
    Environment: 'Dev'
    Owner: 'Renato'
    CostCenter: 'DEV001'
    AutoShutDown: 'false'
    BackupRequired: 'false'
    Criticality: 'Low'
    Monitoring: 'Disabled'
    CreatedBy: 'Bicep'
  }

  sku: {
    name: 'Standard'
  }

  properties: {
    publicIPAllocationMethod: 'Static'
  }
}





//////////////////////////////////// ORPHAN DISK ////////////////////////////////////
resource orphanDisk 'Microsoft.Compute/disks@2023-04-02' = {
  name: 'disk-orphan'
  location: location

  sku: {
    name: 'Standard_LRS'
  }

  properties: {
    creationData: {
      createOption: 'Empty'
    }
    diskSizeGB: 32
  }

  tags: {
    Environment: 'Dev'
    Owner: 'Renato'
    Project: 'ops-toolkit'
    CostCenter: 'DEV001'
    Criticality: 'Low'
    CreatedBy: 'Bicep'
  }
}
