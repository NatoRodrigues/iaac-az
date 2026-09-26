@export()
var vmDevConfig = {
  name: 'vm-dev'
  computerName: 'vm-dev'
  nicName: 'nic-dev'
  osDiskName: 'osdisk-vm-dev'

  environment: 'Dev'
  costCenter: 'DEV001'
  autoShutdown: 'true'
  backupRequired: 'false'
  criticality: 'Low'
}

@export()
var vmProdConfig = {
  name: 'vm-prod'
  computerName: 'vm-prod'
  nicName: 'nic-prod'
  osDiskName: 'osdisk-vm-prod'

  environment: 'Prod'
  costCenter: 'PROD001'
  autoShutdown: 'false'
  backupRequired: 'true'
  criticality: 'High'
}


@export()
var devScriptUri = 'https://raw.githubusercontent.com/NatoRodrigues/iaac-az/main/IaC/scripts/setup-dev.sh'
@export()
var prodScriptUri = 'https://raw.githubusercontent.com/NatoRodrigues/iaac-az/main/IaC/scripts/setup-prod.sh'
