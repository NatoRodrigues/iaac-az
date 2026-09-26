<#
.SYNOPSIS
    Interactively manages VM power states based on automated shutdown eligibility to control compute costs.

.DESCRIPTION
    Provides a menu-driven interface to filter VMs based on their 'AutoShutDown' tag. 
    Allows administrators to safely deallocate (stop and release billing) or start selected VMs during operational hours.

.EXAMPLE
    .\Set-AzVMPowerState.ps1
#>

param(
    [ValidateSet('Start', 'Stop')]
    [string]$Action = "",
    [string]$ResourceGroupName = $env:AZ_OPS_RESOURCE_GROUP,
    [string]$TagKey = "AutoShutDown",
    [string]$TagValue = "true",
    [switch]$Scheduled,
    [switch]$WhatIf
)

Write-Host ""
Write-Host "===================================" -ForegroundColor Cyan
Write-Host "[Ops Toolkit] Setting Azure VM Power State..." -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan
Write-Host ""

if ($WhatIf) {
    Write-Host "WhatIf mode enabled. No changes will be applied." -ForegroundColor Magenta
    Write-Host ""
}

#
# Valida o resource group
#
$rgCheck = az group show `
    --name $ResourceGroupName `
    --query name `
    -o tsv 2>$null

if (-not $rgCheck) {
    Write-Warning "Resource group '$ResourceGroupName' not found or Azure CLI not authenticated."
    Write-Warning "Run 'az login' and try again."
    return
}

Write-Host "Searching VMs with tag '$TagKey=$TagValue'..." -ForegroundColor Cyan
Write-Host ""

#
# Coleta VMs
#
$rawJson = az vm list `
    --resource-group $ResourceGroupName `
    --show-details `
    -o json 2>$null

if (-not $rawJson) {
    Write-Warning "Unable to query virtual machines."
    return
}

$allVms = $rawJson | ConvertFrom-Json

if (-not $allVms) {
    Write-Warning "No virtual machines found in '$ResourceGroupName'."
    return
}

Write-Host "Virtual machines found: $($allVms.Count)" -ForegroundColor Gray

#
# Filtra pela tag
#
$targetVms = foreach ($vm in $allVms) {

    if (-not $vm.tags) { continue }

    foreach ($tag in $vm.tags.PSObject.Properties) {

        if ($tag.Name -ieq $TagKey -and $tag.Value -ieq $TagValue) {
            $vm
            break
        }
    }
}

$targetVms = @($targetVms)

if ($targetVms.Count -eq 0) {

    Write-Warning "No virtual machines found with tag '$TagKey=$TagValue'."
    Write-Host ""
    Write-Host "Available tags:" -ForegroundColor Yellow

    foreach ($vm in $allVms) {

        if ($vm.tags) {

            Write-Host ""
            Write-Host "$($vm.name)" -ForegroundColor White

            foreach ($tag in $vm.tags.PSObject.Properties) {
                Write-Host "  $($tag.Name) = $($tag.Value)" -ForegroundColor DarkGray
            }
        }
    }

    return
}

Write-Host "Target virtual machines: $($targetVms.Count)" -ForegroundColor Green
Write-Host ""

#
# ========== MODO AGENDADO ==========
#
if ($Scheduled) {

    Write-Host "Running in scheduled mode." -ForegroundColor Cyan
    Write-Host ""

    $now = Get-Date
    $currentTime = $now.ToString("HH:mm")
    $dayOfWeek = $now.DayOfWeek.ToString()
    $isWeekend = $dayOfWeek -in @("Saturday", "Sunday")

    Write-Host "Current time: $currentTime ($dayOfWeek)" -ForegroundColor Gray
    Write-Host ""

    $results = foreach ($vm in $targetVms) {

        $startTime = $vm.tags.ScheduleStart
        $shutdownTime = $vm.tags.ScheduleShutdown
        $scheduleDays = $vm.tags.ScheduleDays

        if (-not $shutdownTime) {

            Write-Host "$($vm.name): no schedule tags found." -ForegroundColor DarkGray

            [PSCustomObject]@{
                VmName     = $vm.name
                PowerState = $vm.powerState
                Decision   = "NoSchedule"
                Reason     = "Missing ScheduleShutdown tag"
            }

            continue
        }

        if ($scheduleDays -eq "Weekdays" -and $isWeekend) {

            Write-Host "$($vm.name): weekend, schedule not applicable." -ForegroundColor DarkGray

            [PSCustomObject]@{
                VmName     = $vm.name
                PowerState = $vm.powerState
                Decision   = "Skipped"
                Reason     = "Weekend"
            }

            continue
        }

        $isRunning = $vm.powerState -eq "VM running"

        $shouldBeRunning = (
            $currentTime -ge $startTime -and
            $currentTime -lt $shutdownTime
        )

        $decision = "NoAction"
        $reason = "Already in desired state"

        if ($shouldBeRunning -and -not $isRunning) {

            $decision = "Start"
            $reason = "Inside operating window ($startTime-$shutdownTime)"

            Write-Host "$($vm.name): starting..." -ForegroundColor Green

            if (-not $WhatIf) {
                az vm start `
                    --name $vm.name `
                    --resource-group $vm.resourceGroup `
                    --no-wait `
                    --output none
            }
        }
        elseif (-not $shouldBeRunning -and $isRunning) {

            $decision = "Stop"
            $reason = "Outside operating window ($startTime-$shutdownTime)"

            Write-Host "$($vm.name): deallocating..." -ForegroundColor Yellow

            if (-not $WhatIf) {
                az vm deallocate `
                    --name $vm.name `
                    --resource-group $vm.resourceGroup `
                    --no-wait `
                    --output none
            }
        }
        else {
            Write-Host "$($vm.name): no action needed." -ForegroundColor DarkGray
        }

        [PSCustomObject]@{
            VmName     = $vm.name
            PowerState = $vm.powerState
            Decision   = $decision
            Reason     = $reason
        }
    }

    Write-Host ""
    Write-Host "--- Schedule Evaluation ---" -ForegroundColor Cyan

    $results |
        Sort-Object Decision, VmName |
        Format-Table VmName, PowerState, Decision, Reason -AutoSize

    Write-Host ""
    return
}

#
# ========== MODO INTERATIVO ==========
#
Write-Host "Select the target virtual machine" -ForegroundColor White
Write-Host "Press CTRL + C to cancel" -ForegroundColor DarkGray
Write-Host ""
Write-Host "[0] All virtual machines"

for ($i = 0; $i -lt $targetVms.Count; $i++) {

    $vm = $targetVms[$i]
    $state = $vm.powerState

    Write-Host "[$($i + 1)] $($vm.name)" -NoNewline

    if ($state -eq "VM running") {
        Write-Host "  ($state)" -ForegroundColor Green
    }
    else {
        Write-Host "  ($state)" -ForegroundColor DarkGray
    }
}

Write-Host ""

$input = Read-Host "Option"

if (-not ($input -match '^\d+$')) {
    Write-Warning "Invalid option."
    return
}

$selectedOption = [int]$input

if ($selectedOption -eq 0) {
    $selectedVms = $targetVms
}
elseif ($selectedOption -ge 1 -and $selectedOption -le $targetVms.Count) {
    $selectedVms = @($targetVms[$selectedOption - 1])
}
else {
    Write-Warning "Invalid option."
    return
}

Write-Host ""
Write-Host "Selected virtual machines:" -ForegroundColor Cyan

foreach ($vm in $selectedVms) {
    Write-Host "  $($vm.name) ($($vm.powerState))"
}

Write-Host ""

if (-not $Action) {

    $inputAction = Read-Host "Action (Start / Stop)"

    if ($inputAction -notin @("Start", "Stop")) {
        Write-Warning "Invalid action. Use 'Start' or 'Stop'."
        return
    }

    $Action = $inputAction
}

Write-Host ""

foreach ($vm in $selectedVms) {

    $vmName = $vm.name
    $rgName = $vm.resourceGroup

    Write-Host "VM: $vmName | RG: $rgName" -ForegroundColor White

    if ($WhatIf) {
        Write-Host "  Would execute: $Action" -ForegroundColor Magenta
        continue
    }

    switch ($Action) {

        'Stop' {

            Write-Host "  Deallocating..." -ForegroundColor Yellow

            az vm deallocate `
                --name $vmName `
                --resource-group $rgName `
                --no-wait `
                --output none
        }

        'Start' {

            Write-Host "  Starting..." -ForegroundColor Green

            az vm start `
                --name $vmName `
                --resource-group $rgName `
                --no-wait `
                --output none
        }
    }
}

Write-Host ""
Write-Host "Action '$Action' submitted successfully." -ForegroundColor Green
Write-Host ""

