<#
.SYNOPSIS
    Live monitor for Azure virtual machines.

.DESCRIPTION
    Polls Azure Resource Manager and Azure Monitor to display the current
    power state and CPU usage of every VM in a resource group.
    State transitions are appended to a log file.

.EXAMPLE
    .\Watch-AzVMInventory.ps1

.EXAMPLE
    .\Watch-AzVMInventory.ps1 -RefreshSeconds 30 -WarningThreshold 40
#>

param(
    [string] $ResourceGroup = $env:AZ_OPS_RESOURCE_GROUP,
    [int]    $RefreshSeconds = 60,
    [string] $LogPath = ".\vm-state-changes.log",
    [int]    $BarWidth = 40,
    [double] $WarningThreshold = 70,
    [double] $CriticalThreshold = 90,
    [int]    $HistorySize = 20
)

$ErrorActionPreference = "Stop"

$previousState = @{}
$cpuHistory = @{}

$script:SparkChars = @("_", ".", "-", "=", "+", "*", "^", "#")

Write-Host ""
Write-Host "===================================" -ForegroundColor Cyan
Write-Host "[Ops Toolkit] Viewing Azure VM Inventory..." -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan
Write-Host ""

function Get-CpuBar
{
    param(
        [double] $Percentage,
        [int]    $Width
    )

    $filled = [int](($Percentage / 100) * $Width)

    if ($filled -gt $Width)
    {
        $filled = $Width
    }

    if ($filled -lt 0)
    {
        $filled = 0
    }

    $empty = $Width - $filled

    $bar = ("#" * $filled) + ("." * $empty)

    return $bar
}


function Get-CpuColor
{
    param(
        [double] $Percentage,
        [double] $Warning,
        [double] $Critical
    )

    if ($Percentage -ge $Critical)
    {
        return "Red"
    }

    if ($Percentage -ge $Warning)
    {
        return "Yellow"
    }

    if ($Percentage -ge 5)
    {
        return "Green"
    }

    return "DarkGray"
}


function Get-Sparkline
{
    param(
        [double[]] $Values
    )

    if ($Values.Count -eq 0)
    {
        return ""
    }

    $maxIndex = $script:SparkChars.Count - 1
    $result = ""

    foreach ($value in $Values)
    {
        $index = [int](($value / 100) * $maxIndex)

        if ($index -lt 0)
        {
            $index = 0
        }

        if ($index -gt $maxIndex)
        {
            $index = $maxIndex
        }

        $result = $result + $script:SparkChars[$index]
    }

    return $result
}


function Get-RoundedValue
{
    param(
        [double] $Value
    )

    $scaled = [int]($Value * 100)

    return $scaled / 100
}


function Format-Percentage
{
    param(
        [double] $Value
    )

    $text = $Value.ToString("N2") + "%"

    return $text.PadLeft(8)
}


function Get-VmCpuMetrics
{
    param(
        [string] $ResourceId
    )

    $json = az monitor metrics list --resource $ResourceId --metric "Percentage CPU" --interval PT1M --output json 2>$null

    if (-not $json)
    {
        return @()
    }

    $metrics = $json | ConvertFrom-Json

    if ($metrics.value.Count -eq 0)
    {
        return @()
    }

    if ($metrics.value[0].timeseries.Count -eq 0)
    {
        return @()
    }

    $values = @()

    foreach ($point in $metrics.value[0].timeseries[0].data)
    {
        if ($null -ne $point.average)
        {
            $values = $values + [double]$point.average
        }
    }

    return $values
}


function Get-VmSnapshot
{
    param(
        [string] $ResourceGroupName
    )

    $json = az vm list --resource-group $ResourceGroupName --show-details --output json 2>$null

    if (-not $json)
    {
        return @()
    }

    $vms = $json | ConvertFrom-Json

    $snapshot = @()

    foreach ($vm in $vms)
    {
        $cpuCurrent = $null
        $cpuAverage = $null

        if ($vm.powerState -eq "VM running")
        {
            $values = Get-VmCpuMetrics -ResourceId $vm.id

            if ($values.Count -gt 0)
            {
                $lastValue = $values[-1]
                $avgValue = ($values | Measure-Object -Average).Average

                $cpuCurrent = Get-RoundedValue -Value $lastValue
                $cpuAverage = Get-RoundedValue -Value $avgValue

                if (-not $cpuHistory.ContainsKey($vm.name))
                {
                    $cpuHistory[$vm.name] = @()
                }

                $cpuHistory[$vm.name] = $cpuHistory[$vm.name] + $cpuCurrent

                if ($cpuHistory[$vm.name].Count -gt $HistorySize)
                {
                    $start = $HistorySize * -1
                    $cpuHistory[$vm.name] = $cpuHistory[$vm.name][$start..-1]
                }
            }
        }

        $item = [PSCustomObject]@{
            Name        = $vm.name
            State       = $vm.powerState
            Environment = $vm.tags.Environment
            Criticality = $vm.tags.Criticality
            PrivateIp   = $vm.privateIps
            CpuCurrent  = $cpuCurrent
            CpuAverage  = $cpuAverage
            VmSize      = $vm.hardwareProfile.vmSize
        }

        $snapshot = $snapshot + $item
    }

    return $snapshot
}


function Write-VmHeader
{
    param(
        [string] $ResourceGroupName,
        [string] $Timestamp
    )

    $separator = "-" * 74

    Write-Host ""
    Write-Host "  AZURE VM LIVE MONITOR" -ForegroundColor Cyan
    Write-Host "  Resource Group: $ResourceGroupName" -ForegroundColor DarkGray
    Write-Host "  Last update:    $Timestamp" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  $separator" -ForegroundColor DarkGray
    Write-Host ""
}


function Write-VmDetail
{
    param(
        [PSCustomObject] $Vm
    )

    $stateColor = "DarkGray"

    if ($Vm.State -eq "VM running")
    {
        $stateColor = "Green"
    }

    $environment = $Vm.Environment
    $criticality = $Vm.Criticality

    if (-not $environment)
    {
        $environment = "untagged"
    }

    if (-not $criticality)
    {
        $criticality = "untagged"
    }

    Write-Host "  $($Vm.Name)" -NoNewline -ForegroundColor White
    Write-Host "  [$environment/$criticality]" -NoNewline -ForegroundColor DarkCyan
    Write-Host "  $($Vm.VmSize)" -ForegroundColor DarkGray

    Write-Host "    State:  " -NoNewline -ForegroundColor Gray
    Write-Host $Vm.State -ForegroundColor $stateColor

    if ($null -eq $Vm.CpuCurrent)
    {
        Write-Host "    CPU:    " -NoNewline -ForegroundColor Gray
        Write-Host "no data" -ForegroundColor DarkGray
    }
    else
    {
        $bar = Get-CpuBar -Percentage $Vm.CpuCurrent -Width $BarWidth

        $cpuColor = Get-CpuColor -Percentage $Vm.CpuCurrent -Warning $WarningThreshold -Critical $CriticalThreshold

        $cpuText = Format-Percentage -Value $Vm.CpuCurrent

        Write-Host "    CPU:    " -NoNewline -ForegroundColor Gray
        Write-Host "[$bar]" -NoNewline -ForegroundColor $cpuColor
        Write-Host "  $cpuText" -ForegroundColor $cpuColor

        if ($cpuHistory.ContainsKey($Vm.Name))
        {
            $spark = Get-Sparkline -Values $cpuHistory[$Vm.Name]
            $avgText = Format-Percentage -Value $Vm.CpuAverage

            Write-Host "    Trend:  " -NoNewline -ForegroundColor Gray
            Write-Host $spark -NoNewline -ForegroundColor Cyan
            Write-Host "  avg $avgText" -ForegroundColor DarkGray
        }

        if ($Vm.CpuCurrent -ge $CriticalThreshold)
        {
            Write-Host "    ALERT:  CPU above critical threshold" -ForegroundColor Red
        }
        elseif ($Vm.CpuCurrent -ge $WarningThreshold)
        {
            Write-Host "    WARN:   CPU above warning threshold" -ForegroundColor Yellow
        }
    }

    Write-Host "    IP:     $($Vm.PrivateIp)" -ForegroundColor DarkGray
    Write-Host ""
}


function Write-StateChange
{
    param(
        [PSCustomObject] $Vm,
        [string]         $Timestamp
    )

    if (-not $previousState.ContainsKey($Vm.Name))
    {
        $previousState[$Vm.Name] = $Vm.State
        return
    }

    $oldState = $previousState[$Vm.Name]

    if ($oldState -ne $Vm.State)
    {
        $change = "$Timestamp | $($Vm.Name) | $oldState -> $($Vm.State)"

        Write-Host "    STATE CHANGE: $change" -ForegroundColor Magenta
        Write-Host ""

        Add-Content -Path $LogPath -Value $change
    }

    $previousState[$Vm.Name] = $Vm.State
}


function Write-VmFooter
{
    param(
        [PSCustomObject[]] $Snapshot
    )

    $separator = "-" * 74

    $running = @($Snapshot | Where-Object { $_.State -eq "VM running" }).Count
    $stopped = @($Snapshot | Where-Object { $_.State -ne "VM running" }).Count

    Write-Host "  $separator" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Running: $running    Stopped: $stopped" -NoNewline -ForegroundColor Gray
    Write-Host "    Refresh: $RefreshSeconds sec" -ForegroundColor DarkGray
    Write-Host "  CTRL+C to stop" -ForegroundColor DarkGray
    Write-Host ""
}


#
# Main loop
#

Write-Host "Starting monitor..." -ForegroundColor Cyan

while ($true)
{
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $snapshot = Get-VmSnapshot -ResourceGroupName $ResourceGroup

    Clear-Host

    Write-VmHeader -ResourceGroupName $ResourceGroup -Timestamp $timestamp

    if ($snapshot.Count -eq 0)
    {
        Write-Host "  No virtual machines found." -ForegroundColor Yellow
        Write-Host ""
    }
    else
    {
        foreach ($vm in $snapshot)
        {
            Write-VmDetail -Vm $vm
            Write-StateChange -Vm $vm -Timestamp $timestamp
        }
    }

    Write-VmFooter -Snapshot $snapshot

    Start-Sleep -Seconds $RefreshSeconds
}
