
<#
.SYNOPSIS
    Manages and applies operational tags to Azure resources for lifecycle scheduling.

.DESCRIPTION
    Updates or appends governance tags (e.g., AutoShutDown, Environment, Criticality) on target resources. 
    This enables tag-driven automation and scheduling policies without altering the underlying infrastructure state.

.EXAMPLE
    .\Set-AzTagScheduler.ps1  
#>

param(
    [string]$ResourceGroup = $env:AZ_OPS_RESOURCE_GROUP,

    [string]$VmName = "",

    [ValidatePattern('^([01][0-9]|2[0-3]):[0-5][0-9]$')]
    [string]$StartTime = "08:00",

    [ValidatePattern('^([01][0-9]|2[0-3]):[0-5][0-9]$')]
    [string]$ShutdownTime = "19:00",

    [string]$Timezone = "E. South America Standard Time",

    [ValidateSet("Weekdays", "Daily", "None")]
    [string]$ScheduleDays = "Weekdays",

    [switch]$OnlyAutoShutdownEnabled,

    [switch]$WhatIf
)

Write-Host ""
Write-Host "===================================" -ForegroundColor Cyan
Write-Host "[Ops Toolkit] Setting Azure VM Schedule Tags..." -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan
Write-Host ""

if ($WhatIf) {
    Write-Host "Running in WhatIf mode. No changes will be applied." -ForegroundColor Magenta
    Write-Host ""
}

#
# Coleta VMs
#
$vms = az vm list `
    --resource-group $ResourceGroup `
    --output json | ConvertFrom-Json

if (-not $vms) {
    Write-Warning "No virtual machines found in resource group '$ResourceGroup'."
    return
}

if ($VmName) {

    $vms = $vms | Where-Object { $_.name -eq $VmName }

    if (-not $vms) {
        Write-Warning "Virtual machine '$VmName' not found."
        return
    }
}

if ($OnlyAutoShutdownEnabled) {

    $vms = $vms | Where-Object { $_.tags.AutoShutDown -eq "true" }

    if (-not $vms) {
        Write-Warning "No virtual machines with AutoShutDown enabled."
        return
    }
}

Write-Host "Target virtual machines: $($vms.Count)" -ForegroundColor Gray
Write-Host ""

#
# Aplica tags
#
$results = foreach ($vm in $vms) {

    $environment = $vm.tags.Environment
    $criticality = $vm.tags.Criticality

    #
    # Proteção: Prod ou High nunca recebe agendamento automático
    #
    if ($criticality -eq "High" -or $environment -eq "Prod") {

        Write-Host "Skipping $($vm.name)" -ForegroundColor DarkYellow
        Write-Host "  Reason: Criticality=$criticality Environment=$environment" -ForegroundColor DarkGray

        [PSCustomObject]@{
            VmName       = $vm.name
            Environment  = $environment
            Criticality  = $criticality
            Action       = "Skipped"
            StartTime    = $vm.tags.ScheduleStart
            ShutdownTime = $vm.tags.ScheduleShutdown
            ScheduleDays = $vm.tags.ScheduleDays
            Timezone     = $vm.tags.ScheduleTimezone
        }

        continue
    }

    Write-Host "Tagging $($vm.name)..." -ForegroundColor Yellow

    $tags = @(
        "ScheduleStart=$StartTime",
        "ScheduleShutdown=$ShutdownTime",
        "ScheduleDays=$ScheduleDays",
        "ScheduleTimezone=$Timezone",
        "ScheduleManagedBy=ops-toolkit"
    )

    if ($WhatIf) {

        Write-Host "  Would apply:" -ForegroundColor Magenta

        foreach ($tag in $tags) {
            Write-Host "    $tag" -ForegroundColor DarkGray
        }

        $action = "WhatIf"
    }
    else {

        az resource tag `
            --ids $vm.id `
            --tags $tags `
            --is-incremental `
            --output none

        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Applied successfully." -ForegroundColor Green
            $action = "Applied"
        }
        else {
            Write-Host "  Failed to apply tags." -ForegroundColor Red
            $action = "Failed"
        }
    }

    [PSCustomObject]@{
        VmName       = $vm.name
        Environment  = $environment
        Criticality  = $criticality
        Action       = $action
        StartTime    = $StartTime
        ShutdownTime = $ShutdownTime
        ScheduleDays = $ScheduleDays
        Timezone     = $Timezone
    }
}
 
Write-Host ""
Write-Host "--- Schedule Summary ---" -ForegroundColor Cyan

$results |
    Sort-Object Action, VmName |
    Format-Table `
        VmName,
        Environment,
        Criticality,
        Action,
        StartTime,
        ShutdownTime,
        ScheduleDays `
        -AutoSize

$applied = ($results | Where-Object Action -eq "Applied").Count
$skipped = ($results | Where-Object Action -eq "Skipped").Count
$failed = ($results | Where-Object Action -eq "Failed").Count

Write-Host ""
Write-Host "Applied: $applied" -ForegroundColor Green
Write-Host "Skipped: $skipped" -ForegroundColor DarkYellow

if ($failed -gt 0) {
    Write-Host "Failed:  $failed" -ForegroundColor Red
}

Write-Host ""