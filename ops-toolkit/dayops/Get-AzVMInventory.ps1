<#
.SYNOPSIS
    Retrieves and displays a detailed inventory of Virtual Machines in a Resource Group.

.DESCRIPTION
    Queries the Azure environment for VM power states, network configurations, and assigned governance tags. 
    Outputs a formatted console table to provide a quick operational overview for Day-2 management.

.EXAMPLE
    .\Get-AzVMInventory.ps1
#>


param(
    [string]$ResourceGroup = $env:AZ_OPS_RESOURCE_GROUP,
    [string]$OutputPath = ".\VMInventoryReport.csv",
    [switch]$Continuous,
    [int]$IntervalHours = 2
)



Write-Host ""
Write-Host "===================================" -ForegroundColor Cyan
Write-Host "[Ops Toolkit] Collecting Azure VM Inventory..." -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan
Write-Host ""

$vms = az vm list `
    --resource-group $ResourceGroup `
    --show-details `
    --output json | ConvertFrom-Json

if (-not $vms) {
    Write-Warning "No virtual machines found in resource group '$ResourceGroup'."
    return
}

Write-Host "Virtual machines found: $($vms.Count)" -ForegroundColor Gray
Write-Host ""

$inventory = foreach ($vm in $vms) {

    Write-Host "Collecting $($vm.name)..." -ForegroundColor Yellow

    $nicName = $null
    $subnetName = $null
    $vnetName = $null

    if ($vm.networkProfile.networkInterfaces.Count -gt 0) {

        $nicId = $vm.networkProfile.networkInterfaces[0].id
        $nicName = ($nicId -split "/")[-1]

        $nic = az network nic show `
            --ids $nicId `
            --output json | ConvertFrom-Json

        if ($nic.ipConfigurations.Count -gt 0) {

            $subnetId = $nic.ipConfigurations[0].subnet.id

            if ($subnetId) {
                $subnetParts = $subnetId -split "/"
                $subnetName = $subnetParts[-1]
                $vnetName = $subnetParts[-3]
            }
        }
    }

    $osDiskName = $vm.storageProfile.osDisk.name
    $osDiskSize = $vm.storageProfile.osDisk.diskSizeGb
    $osDiskType = $vm.storageProfile.osDisk.managedDisk.storageAccountType

    $imagePublisher = $vm.storageProfile.imageReference.publisher
    $imageOffer = $vm.storageProfile.imageReference.offer
    $imageSku = $vm.storageProfile.imageReference.sku

    [PSCustomObject]@{
        Name            = $vm.name
        PowerState      = $vm.powerState
        Location        = $vm.location
        VmSize          = $vm.hardwareProfile.vmSize
        OsType          = $vm.storageProfile.osDisk.osType

        Image           = "$imagePublisher/$imageOffer/$imageSku"

        AdminUsername   = $vm.osProfile.adminUsername
        ComputerName    = $vm.osProfile.computerName

        PrivateIp       = $vm.privateIps
        PublicIp        = $vm.publicIps

        Nic             = $nicName
        Vnet            = $vnetName
        Subnet          = $subnetName

        OsDiskName      = $osDiskName
        OsDiskSizeGb    = $osDiskSize
        OsDiskType      = $osDiskType
        DataDiskCount   = $vm.storageProfile.dataDisks.Count

        Environment     = $vm.tags.Environment
        Criticality     = $vm.tags.Criticality
        CostCenter      = $vm.tags.CostCenter
        AutoShutdown    = $vm.tags.AutoShutDown
        BackupRequired  = $vm.tags.BackupRequired
        Monitoring      = $vm.tags.Monitoring
        Owner           = $vm.tags.Owner

        ResourceId      = $vm.id
    }
}

#
# Exporta CSV
#
$inventory |
    Export-Csv `
        $OutputPath `
        -NoTypeInformation `
        -Encoding UTF8

#
# Visão geral
#
Write-Host ""
Write-Host "--- Overview ---" -ForegroundColor Cyan

$inventory |
    Sort-Object Environment, Name |
    Format-Table `
        Name,
        PowerState,
        VmSize,
        Environment,
        Criticality,
        PrivateIp `
        -AutoSize

#
# Visão de rede
#
Write-Host "--- Network ---" -ForegroundColor Cyan

$inventory |
    Sort-Object Name |
    Format-Table `
        Name,
        Vnet,
        Subnet,
        Nic,
        PrivateIp,
        PublicIp `
        -AutoSize

#
# Visão de storage
#
Write-Host "--- Storage ---" -ForegroundColor Cyan

$inventory |
    Sort-Object Name |
    Format-Table `
        Name,
        OsDiskName,
        OsDiskSizeGb,
        OsDiskType,
        DataDiskCount `
        -AutoSize

#
# Sumário
#
$running = ($inventory | Where-Object PowerState -eq "VM running").Count
$stopped = ($inventory | Where-Object PowerState -ne "VM running").Count
$untagged = ($inventory | Where-Object { -not $_.Environment }).Count

Write-Host ""
Write-Host "Total VMs:     $($inventory.Count)" -ForegroundColor White
Write-Host "Running:       $running" -ForegroundColor Green
Write-Host "Stopped:       $stopped" -ForegroundColor Gray
Write-Host "Untagged:      $untagged" -ForegroundColor $(if ($untagged -gt 0) { "Yellow" } else { "Gray" })
Write-Host ""
Write-Host "Report saved to: $OutputPath" -ForegroundColor Green

if ($Continuous) {

    while ($true) {

        Write-Host ""
        Write-Host "Next execution in $IntervalHours hour(s)." -ForegroundColor Cyan
        Write-Host "Press CTRL+C to stop." -ForegroundColor DarkGray

        Start-Sleep -Seconds ($IntervalHours * 3600)

        & $PSCommandPath -ResourceGroup $ResourceGroup
    }
}