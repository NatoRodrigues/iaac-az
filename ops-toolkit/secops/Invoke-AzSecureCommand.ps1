<#
.SYNOPSIS
    Securely executes commands on Azure VMs without the need for Public IPs or open SSH ports.

.DESCRIPTION
    This script uses the Azure VM Run Command extension to inject and execute 
    Shell commands directly through the Azure management bus (SecOps).

.EXAMPLE
    .\Invoke-AzSecureCommand.ps1 -ResourceGroup "rg-renato-iac" -VMName "vm-dev" -Command "uptime && free -h"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, HelpMessage = "Resource Group Name")]
    [string]$ResourceGroup,
    [Parameter(Mandatory = $true, HelpMessage = "Virtual Machine Name")]
    [string]$VMName,
    [Parameter(Mandatory = $true, HelpMessage = "Bash command to execute")]
    [string]$Command
)

Write-Host ""
Write-Host "===================================" -ForegroundColor Cyan
Write-Host "[Ops Toolkit] Running Secure Command on Azure VM..." -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan
Write-Host ""

try {
    Write-Host "`n[SecOps] Starting secure command execution on VM: $VMName" -ForegroundColor Cyan
    Write-Host "Command: $Command" -ForegroundColor DarkGray

    # Check if the VM exists and is running
    $vmState = az vm get-instance-view --resource-group $ResourceGroup --name $VMName --query "instanceView.statuses[?starts_with(code, 'PowerState/')].displayStatus" -o tsv
    
    if ($vmState -ne "VM running") {
        Write-Warning "The VM '$VMName' is not running. Current state: $vmState. Start the VM before executing commands."
        return
    }

    $os = az vm show --resource-group $ResourceGroup --name $VMName --query "storageProfile.osDisk.osType" -o tsv
    $cmd = if ($os -ieq "Windows") { "RunPowerShellScript" } else { "RunShellScript" }

    Write-host "Detected OS" $os -ForegroundColor Gray "-> using" $cmd -ForegroundColor Cyan
    Write-Host "Injecting script via Azure Run Command (this may take 1 to 2 minutes)..." -ForegroundColor Yellow

    # Execute the command via Azure CLI
    $result = az vm run-command invoke `
        --command-id $cmd `
        --name $VMName `
        --resource-group $ResourceGroup `
        --scripts $Command `
        --output json | ConvertFrom-Json

    Write-Host "`n[Execution Result]" -ForegroundColor Green
    Write-Host "----------------------------------------"
    
    # The Run Command output usually comes inside the 'value' property in the first item
    $message = $result.value[0].message
    Write-Host $message
    Write-Host "----------------------------------------`n"

}
catch {
    Write-Error "Failed to execute secure command: $_"
}