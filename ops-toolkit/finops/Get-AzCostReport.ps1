<#
.SYNOPSIS
    Generates a summary of resource spending based on operational tags and environments.

.DESCRIPTION
    Aggregates cost and billing metrics for resources within the environment. 
    Groups data by metadata tags (such as Environment, Project, or Owner) to provide FinOps visibility into financial allocation.

.EXAMPLE
    .\Get-AzCostReport.ps1
#>

Write-Host "Retrieving Subscription ID..." -ForegroundColor Cyan
$subId = (az account show --query id -o tsv 2>$null)

if (-not $subId) {
    Write-Warning "Unable to retrieve active subscription. Run 'az login' first."
    return
}

$subName = (az account show --query name -o tsv)
Write-Host "Active Subscription: $subName" -ForegroundColor Gray

# Build payload object
$bodyObject = @{
    type = "ActualCost"
    timeframe = "MonthToDate"
    dataset = @{
        granularity = "None"
        aggregation = @{
            totalCost = @{
                name = "PreTaxCost"
                function = "Sum"
            }
        }
        grouping = @(
            @{
                type = "Dimension"
                name = "ResourceId"
            }
        )
    }
}


$jsonBody = $bodyObject | ConvertTo-Json -Depth 10

# Save payload to a temporary file to prevent shell escaping issues
$tempFile = [System.IO.Path]::GetTempFileName()
Set-Content -Path $tempFile -Value $jsonBody

$uri = "https://management.azure.com/subscriptions/$subId/providers/Microsoft.CostManagement/query?api-version=2023-03-01"

Write-Host "Querying Cost Management API via REST..." -ForegroundColor Cyan

# Execute az rest using the JSON payload file
$response = az rest --method post --uri $uri --body "@$tempFile" --output json 2>$null

Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue

if (-not $response) {
    Write-Warning "API returned no data. Inspect the direct error output below:"
    az rest --method post --uri $uri --body $jsonBody
    return
}

$costData = $response | ConvertFrom-Json

# Process results
$report = foreach ($row in $costData.properties.rows) {
    $cost = [double]$row[0]
    $resourceId = $row[1]
    
    $resourceName = ($resourceId -split "/")[-1]
    $resourceGroup = if ($resourceId -match "/resourceGroups/([^/]+)/") { $Matches[1] } else { "N/A" }
    
    [PSCustomObject]@{
        Resource      = $resourceName
        ResourceGroup = $resourceGroup
        CostUSD       = [math]::Round($cost, 4)
    }
}

$topConsumers = $report | Where-Object { $_.CostUSD -gt 0 } | Sort-Object CostUSD -Descending | Select-Object -First 15

Write-Host ""
Write-Host "===================================" -ForegroundColor Cyan
Write-Host "[Ops Toolkit] Azure resources top consumers (Month-To-Date)..." -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan
Write-Host ""

if ($topConsumers) {
    $topConsumers | Format-Table -AutoSize
    $total = ($report | Measure-Object -Property CostUSD -Sum).Sum
    Write-Host "MONTH-TO-DATE TOTAL: USD $([math]::Round($total, 2))`n" -ForegroundColor Green
} else {
    Write-Host "No billable consumption recorded for the current month so far." -ForegroundColor Yellow
}