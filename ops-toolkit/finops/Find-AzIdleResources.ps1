<#
.SYNOPSIS
    Scans for unattached or idle Azure resources to optimize cloud costs.

.DESCRIPTION
    Identifies orphaned managed disks and unassociated Public IP addresses within the specified Resource Group. 
    Helps FinOps teams detect waste, prevent unnecessary billing, and report findings before applying destructive remediation.

.EXAMPLE
    .\Find-AzIdleResources.ps1  
#>

param(
    [string]$ResourceGroup = $env:AZ_OPS_RESOURCE_GROUP,
    [double]$CpuThreshold = 5,
    [string]$WebhookUri = "",
    [string]$OutputPath = ".\IdleResourcesReport.csv"
)

function Test-IsVmIdle {
    param(
        [double]$CpuAverage,
        [double]$Threshold
    )

    return ($CpuAverage -lt $Threshold)
}

$supportedTypes = @(
    "Microsoft.Compute/virtualMachines",
    "Microsoft.Compute/disks",
    "Microsoft.Network/networkInterfaces",
    "Microsoft.Network/publicIPAddresses",
    "Microsoft.Storage/storageAccounts"
)

Write-Host ""
Write-Host "===================================" -ForegroundColor Cyan
Write-Host "[Ops Toolkit] Resource Usage Assessment..." -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan
Write-Host ""

$allResources = az resource list `
    --resource-group $ResourceGroup `
    --output json | ConvertFrom-Json

$resources = $allResources | Where-Object {
    $_.type -in $supportedTypes
}

Write-Host "Resources found: $($allResources.Count)" -ForegroundColor Gray
Write-Host "Resources analyzed: $($resources.Count)" -ForegroundColor Gray
Write-Host ""

$report = foreach ($resource in $resources) {

    $criticality = $resource.tags.Criticality
    $environment = $resource.tags.Environment

    $cpuAverage = $null
    $idleStatus = "N/A"

    switch ($resource.type) {

        #
        # VMs - análise por métrica de CPU
        #
        "Microsoft.Compute/virtualMachines" {

            Write-Host "Checking VM $($resource.name)..." -ForegroundColor Yellow

            $metrics = az monitor metrics list `
                --resource $resource.id `
                --metric "Percentage CPU" `
                --output json | ConvertFrom-Json

            $cpuValues = @()

            if (
                $metrics.value.Count -gt 0 -and
                $metrics.value[0].timeseries.Count -gt 0
            ) {

                foreach ($item in $metrics.value[0].timeseries[0].data) {

                    if ($null -ne $item.average) {
                        $cpuValues += [double]$item.average
                    }
                }
            }

            if ($cpuValues.Count -gt 0) {

                $average = ($cpuValues | Measure-Object -Average).Average

                $cpuAverage = [System.Math]::Round($average, 2)

                if (Test-IsVmIdle -CpuAverage $cpuAverage -Threshold $CpuThreshold) {
                    $idleStatus = "Idle"
                }
                else {
                    $idleStatus = "Active"
                }
            }
        }

        #
        # Discos - análise por associação
        #
        "Microsoft.Compute/disks" {

            Write-Host "Checking Disk $($resource.name)..." -ForegroundColor Yellow

            $disk = az disk show `
                --ids $resource.id `
                --output json | ConvertFrom-Json

            if ($disk.diskState -eq "Unattached") {
                $idleStatus = "Orphan"
            }
            else {
                $idleStatus = "Attached"
            }
        }

        #
        # NICs - análise por associação
        #
        "Microsoft.Network/networkInterfaces" {

            Write-Host "Checking NIC $($resource.name)..." -ForegroundColor Yellow

            $nic = az network nic show `
                --ids $resource.id `
                --output json | ConvertFrom-Json

            if ($null -eq $nic.virtualMachine) {
                $idleStatus = "Orphan"
            }
            else {
                $idleStatus = "Attached"
            }
        }

        #
        # Public IPs - análise por associação
        #
        "Microsoft.Network/publicIPAddresses" {

            Write-Host "Checking Public IP $($resource.name)..." -ForegroundColor Yellow

            $pip = az network public-ip show `
                --ids $resource.id `
                --output json | ConvertFrom-Json

            if ($null -eq $pip.ipConfiguration) {
                $idleStatus = "Orphan"
            }
            else {
                $idleStatus = "Attached"
            }
        }

        #
        # Storage Accounts - análise por transações
        #
        "Microsoft.Storage/storageAccounts" {

            Write-Host "Checking Storage $($resource.name)..." -ForegroundColor Yellow

            $metrics = az monitor metrics list `
                --resource $resource.id `
                --metric "Transactions" `
                --aggregation Total `
                --output json | ConvertFrom-Json

            $totalTransactions = 0

            if (
                $metrics.value.Count -gt 0 -and
                $metrics.value[0].timeseries.Count -gt 0
            ) {

                foreach ($item in $metrics.value[0].timeseries[0].data) {

                    if ($null -ne $item.total) {
                        $totalTransactions += [double]$item.total
                    }
                }
            }

            if ($totalTransactions -lt 10) {
                $idleStatus = "Idle"
            }
            else {
                $idleStatus = "Active"
            }
        }
    }

    #
    # Recomendação baseada nas tags
    #
    $needsAttention = $idleStatus -in @("Idle", "Orphan")

    $recommendation = switch ($criticality) {

        "High" {
            if ($needsAttention) { "ManualReview" } else { "NoAction" }
        }

        "Low" {
            if ($needsAttention) { "ShutdownCandidate" } else { "NoAction" }
        }

        default {
            if ($needsAttention) { "Review" } else { "NoAction" }
        }
    }

    [PSCustomObject]@{
        ResourceName   = $resource.name
        ResourceType   = $resource.type
        Environment    = $environment
        Criticality    = $criticality
        CostCenter     = $resource.tags.CostCenter
        AutoShutdown   = $resource.tags.AutoShutdown
        Monitoring     = $resource.tags.Monitoring
        CpuAverage     = $cpuAverage
        IdleStatus     = $idleStatus
        Recommendation = $recommendation
    }
}

#
# Exporta CSV
#
$report |
    Export-Csv `
        $OutputPath `
        -NoTypeInformation `
        -Encoding UTF8

#
# Exibe console
#
Write-Host ""

$report |
    Sort-Object IdleStatus, ResourceName |
    Format-Table `
        ResourceName,
        Environment,
        Criticality,
        CpuAverage,
        IdleStatus,
        Recommendation `
        -AutoSize

#
# Sumário
#
$needsAttention = $report | Where-Object {
    $_.IdleStatus -in @("Idle", "Orphan")
}

Write-Host ""
Write-Host "Report generated successfully." -ForegroundColor Green
Write-Host "File: $OutputPath" -ForegroundColor Green
Write-Host ""
Write-Host "Resources requiring attention: $($needsAttention.Count)" -ForegroundColor Yellow

#
# Webhook opcional
#
if ($needsAttention.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($W)) {

    Write-Host "Sending webhook notification..." -ForegroundColor Cyan

    $payload = @{
        subject   = "Azure Resource Usage Report"
        count     = $needsAttention.Count
        resources = $needsAttention
    } | ConvertTo-Json -Depth 5

    Invoke-RestMethod `
        -Uri $WebhookUri `
        -Method Post `
        -ContentType "application/json" `
        -Body $payload
}

if ($needsAttention.Count -gt 0) {
    exit 2
}

exit 0