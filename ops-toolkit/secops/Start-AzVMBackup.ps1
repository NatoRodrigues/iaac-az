<#
.SYNOPSIS
    Tag-based VM backup: audits, provisions a Recovery Services Vault, enables protection and triggers on-demand backups.

.DESCRIPTION
    Finds VMs in the Resource Group with tag BackupRequired='true' (or a single VM via -VMName).
    - Without -VaultName: Audit mode (reports which VMs need protection and whether they are already protected).
    - With -VaultName:    Ensures the vault exists. If missing, asks the user for confirmation
                          (showing a cost warning) before creating it in the VM region,
                          enables protection with the chosen policy and triggers an on-demand backup.

.EXAMPLE
    .\Start-AzVMBackup.ps1 -ResourceGroup "rg-renato"

.EXAMPLE
    .\Start-AzVMBackup.ps1 -ResourceGroup "rg-renato" -VaultName "rsv-renato"

.EXAMPLE
    .\Start-AzVMBackup.ps1 -ResourceGroup "rg-renato" -VaultName "rsv-renato" -VMName "vm-dev" -RetentionDays 7
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, HelpMessage = "Resource Group Name")]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $false, HelpMessage = "Recovery Services Vault Name (omit for Audit mode)")]
    [string]$VaultName = "",

    [Parameter(Mandatory = $false, HelpMessage = "Target a single VM (overrides the tag filter)")]
    [string]$VMName = "",

    [Parameter(Mandatory = $false, HelpMessage = "Backup policy in the vault")]
    [string]$PolicyName = "DefaultPolicy",

    [Parameter(Mandatory = $false, HelpMessage = "Days to retain the on-demand recovery point")]
    [ValidateRange(1, 365)]
    [int]$RetentionDays = 30
)

# ---------------------------------------------------------------------------
# Module 1: ensure the Recovery Services Vault exists (same region as the VM)
# ---------------------------------------------------------------------------
function Get-BackupVault {
    param (
        [string]$ResourceGroup,
        [string]$VaultName
    )

    return az backup vault list --resource-group $ResourceGroup `
        --query "[?name=='$VaultName'] | [0]" --output json | ConvertFrom-Json
}

Write-Host ""
Write-Host "===================================" -ForegroundColor Cyan
Write-Host "[Ops Toolkit] Starting Azure VM Backup..." -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan
Write-Host ""

function Confirm-VaultCreation {
    param (
        [string]$VaultName
    )

    Write-Host "`n[!] Recovery Services Vault '$VaultName' does not exist." -ForegroundColor Yellow
    Write-Host "    COST WARNING: creating a vault and protecting VMs WILL incur Azure charges:" -ForegroundColor Red
    Write-Host "      - Protected instance fee (per VM, based on its size)" -ForegroundColor Red
    Write-Host "      - Backup storage consumed by recovery points (default redundancy: GRS)" -ForegroundColor Red
    Write-Host "    Charges continue until protection is disabled and backup data is deleted" -ForegroundColor Red
    Write-Host "    (soft delete keeps data for 14 days)." -ForegroundColor Red

    do {
        $answer = (Read-Host "`n    Do you want to create the vault and proceed? (Y/N)").Trim().ToUpper()
    } while ($answer -notin @('Y', 'N'))

    return ($answer -eq 'Y')
}

function Initialize-BackupVault {
    param (
        [string]$ResourceGroup,
        [string]$VaultName,
        [string]$Location,
        [bool]$CreateVault = $false
    )

    $existing = Get-BackupVault -ResourceGroup $ResourceGroup -VaultName $VaultName

    if ($existing) {
        if ($existing.location -ne $Location) {
            throw "Vault '$VaultName' is in '$($existing.location)', but the VM is in '$Location'. Vault and VM must be in the same region."
        }
        Write-Host "  [=] Vault '$VaultName' already exists ($($existing.location))." -ForegroundColor DarkGray
        return $true
    }

    if (-not $CreateVault) {
        Write-Warning "  Vault '$VaultName' does not exist and creation was declined. Skipping."
        return $false
    }

    Write-Host "  [+] Creating Recovery Services Vault '$VaultName' in '$Location'..." -ForegroundColor Yellow
    az backup vault create --resource-group $ResourceGroup --name $VaultName --location $Location --output none
    if ($LASTEXITCODE -ne 0) { throw "Failed to create vault '$VaultName'." }

    Write-Host "  [OK] Vault created." -ForegroundColor Green
    return $true
}

# ---------------------------------------------------------------------------
# Module 2: enable protection (associate the VM with a policy in the vault)
# ---------------------------------------------------------------------------
function Enable-VMProtection {
    param (
        [string]$ResourceGroup,
        [string]$VaultName,
        [object]$VM,
        [string]$PolicyName
    )

    # Returns the vault ID if the VM is already protected, empty otherwise
    $protectedBy = az backup protection check-vm --resource-group $ResourceGroup --vm $VM.name --output tsv

    if ($protectedBy) {
        $currentVault = ($protectedBy -split '/')[-1]
        if ($currentVault -ne $VaultName) {
            Write-Warning "  VM '$($VM.name)' is already protected by another vault ('$currentVault'). Skipping."
            return $false
        }
        Write-Host "  [=] VM '$($VM.name)' is already protected in '$VaultName'." -ForegroundColor DarkGray
        return $true
    }

    Write-Host "  [+] Enabling protection for '$($VM.name)' with policy '$PolicyName' (may take 1-2 min)..." -ForegroundColor Yellow
    az backup protection enable-for-vm `
        --resource-group $ResourceGroup `
        --vault-name $VaultName `
        --vm $VM.id `
        --policy-name $PolicyName `
        --output none

    if ($LASTEXITCODE -ne 0) {
        Write-Warning "  Failed to enable protection for '$($VM.name)'."
        return $false
    }

    Write-Host "  [OK] Protection enabled." -ForegroundColor Green
    return $true
}

# ---------------------------------------------------------------------------
# Module 3: trigger the on-demand backup
# ---------------------------------------------------------------------------
function Start-OnDemandBackup {
    param (
        [string]$ResourceGroup,
        [string]$VaultName,
        [string]$VMName,
        [int]$RetentionDays
    )

    # Resolve the real container/item names registered in the vault
    $item = az backup item list `
        --resource-group $ResourceGroup `
        --vault-name $VaultName `
        --backup-management-type AzureIaasVM `
        --workload-type VM `
        --query "[?properties.friendlyName=='$VMName'] | [0]" `
        --output json | ConvertFrom-Json

    if (-not $item) {
        Write-Warning "  Backup item for '$VMName' not found in vault '$VaultName'."
        return $null
    }

    $retainUntil = (Get-Date).AddDays($RetentionDays).ToString("dd-MM-yyyy")

    $job = az backup protection backup-now `
        --resource-group $ResourceGroup `
        --vault-name $VaultName `
        --container-name $item.properties.containerName `
        --item-name $item.name `
        --backup-management-type AzureIaasVM `
        --retain-until $retainUntil `
        --output json | ConvertFrom-Json

    if ($LASTEXITCODE -ne 0 -or -not $job) {
        Write-Warning "  Failed to start backup for '$VMName'."
        return $null
    }

    Write-Host "  [OK] Backup job started for '$VMName' (retain until $retainUntil)." -ForegroundColor Green
    return $job.name
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
try {
    Write-Host "`n[SecOps] Starting tag-based backup audit and routine..." -ForegroundColor Cyan

    # 1. Resolve target VMs
    if ($VMName) {
        Write-Host "Target VM: $VMName (Resource Group: $ResourceGroup)`n" -ForegroundColor DarkGray
        $vm = az vm show --resource-group $ResourceGroup --name $VMName --output json | ConvertFrom-Json
        if (-not $vm) { throw "VM '$VMName' not found in '$ResourceGroup'." }

        if ($vm.tags.BackupRequired -ne 'true') {
            Write-Warning "VM '$VMName' does not have tag BackupRequired='true'. Proceeding because it was explicitly requested."
        }
        $vmsToBackup = @($vm)
    }
    else {
        Write-Host "Searching for VMs in '$ResourceGroup' with tag BackupRequired='true'`n" -ForegroundColor DarkGray
        $vms = az vm list --resource-group $ResourceGroup --output json | ConvertFrom-Json
        # -eq is case-insensitive in PowerShell ('true' == 'True')
        $vmsToBackup = @($vms | Where-Object { $_.tags.BackupRequired -eq 'true' })
    }

    if ($vmsToBackup.Count -eq 0) {
        Write-Host "No VMs found with tag BackupRequired='true'." -ForegroundColor Green
        return
    }

    Write-Host "VMs identified for protection:" -ForegroundColor Yellow
    $vmsToBackup | Format-Table Name, Location, @{ Name = "Tags"; Expression = { $_.tags | ConvertTo-Json -Compress } }

    # 2. Audit mode
    if (-not $vaultName -or $vaultName.Trim() -eq "") {
        Write-Host "Audit Mode: no Recovery Services Vault provided.`n" -ForegroundColor Yellow

        $vmsToBackup | ForEach-Object {
            $protectedBy = az backup protection check-vm --resource-group $ResourceGroup --vm $_.name --output tsv
            [PSCustomObject]@{
                VM        = $_.name
                Protected = [bool]$protectedBy
                Vault     = if ($protectedBy) { ($protectedBy -split '/')[-1] } else { "-" }
            }
        } | Format-Table -AutoSize

        Write-Host "Run again with -VaultName to provision the vault and back up unprotected VMs." -ForegroundColor White
        return
    }

    # 3. Ask once whether the vault may be created (only if it does not exist yet)
    $createVault = $false
    if (-not (Get-BackupVault -ResourceGroup $ResourceGroup -VaultName $VaultName)) {
        $createVault = Confirm-VaultCreation -VaultName $VaultName

        if (-not $createVault) {
            Write-Host "`nOperation cancelled by user. No resources were created and no costs were incurred.`n" -ForegroundColor Yellow
            return
        }
    }

    # 4. Provision + protect + backup
    $summary = foreach ($vm in $vmsToBackup) {
        Write-Host "`n-> Processing VM: $($vm.name)" -ForegroundColor Cyan
        $status = "Failed"
        $jobId  = "-"

        try {
            $vaultReady = Initialize-BackupVault -ResourceGroup $ResourceGroup -VaultName $VaultName -Location $vm.location -CreateVault $createVault
            if (-not $vaultReady) {
                [PSCustomObject]@{ VM = $vm.name; Status = "Skipped (no vault)"; JobId = "-" }
                continue
            }

            $isProtected = Enable-VMProtection -ResourceGroup $ResourceGroup -VaultName $VaultName -VM $vm -PolicyName $PolicyName

            if ($isProtected) {
                $job = Start-OnDemandBackup -ResourceGroup $ResourceGroup -VaultName $VaultName -VMName $vm.name -RetentionDays $RetentionDays
                if ($job) { $status = "BackupStarted"; $jobId = $job }
            }
        }
        catch {
            Write-Warning "  $($_.Exception.Message)"
        }

        [PSCustomObject]@{ VM = $vm.name; Status = $status; JobId = $jobId }
    }

    Write-Host "`n[Summary]" -ForegroundColor Cyan
    $summary | Format-Table -AutoSize

    Write-Host "Track progress with:" -ForegroundColor DarkGray
    Write-Host "  az backup job list --resource-group $ResourceGroup --vault-name $VaultName -o table" -ForegroundColor DarkGray

    Write-Host "`nSecOps operation completed.`n" -ForegroundColor Cyan
}
catch {
    Write-Error "Failed to process backup routine: $_"
}