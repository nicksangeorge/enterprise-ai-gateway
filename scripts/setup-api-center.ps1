#Requires -Version 7.0
<#
.SYNOPSIS
    Configures API Center to sync APIs from APIM.
    Enables managed identity, grants RBAC, creates integration.

.DESCRIPTION
    Run after APIM is deployed and MCP server is registered.
    Requires the apic-extension (installed automatically).

.EXAMPLE
    .\setup-api-center.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Step {
    param([int]$Number, [string]$Title)
    Write-Host ""
    Write-Host ("=" * 65) -ForegroundColor Cyan
    Write-Host "  Step ${Number}: $Title" -ForegroundColor Cyan
    Write-Host ("=" * 65) -ForegroundColor Cyan
}

function Write-Ok   { param([string]$M) Write-Host "  [OK] $M" -ForegroundColor Green }
function Write-Info { param([string]$M) Write-Host "  $M" -ForegroundColor Yellow }
function Write-Err  { param([string]$M) Write-Host "  [FAIL] $M" -ForegroundColor Red }

# ── Step 1: Read terraform outputs ──────────────────────────────────────────

Write-Step 1 "Reading terraform outputs"

$tfDir = Join-Path $PSScriptRoot "..\infra\terraform"
Push-Location $tfDir
try {
    $tf = terraform output -json 2>&1 | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw "terraform output failed" }
} finally { Pop-Location }

$rg       = $tf.resource_group_name.value
$apimName = $tf.apim_name.value
$subId    = (az account show --query id -o tsv).Trim()

# Derive API Center name from APIM name pattern (aigw-apim-xxxx -> aigw-apicenter-xxxx)
$suffix = $apimName -replace '^aigw-apim-', ''
$apiCenterName = "aigw-apicenter-$suffix"

Write-Ok "Resource group : $rg"
Write-Ok "APIM           : $apimName"
Write-Ok "API Center     : $apiCenterName"
Write-Ok "Subscription   : $subId"

# Verify API Center exists
$acCheck = az resource show -g $rg --resource-type "Microsoft.ApiCenter/services" -n $apiCenterName --query "name" -o tsv 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Err "API Center '$apiCenterName' not found in resource group '$rg'"
    exit 1
}

# ── Step 2: Enable managed identity ─────────────────────────────────────────

Write-Step 2 "Enabling managed identity on API Center"

$tempFile = New-TemporaryFile
'{"identity":{"type":"SystemAssigned"}}' | Set-Content $tempFile.FullName
$apicIdentity = az rest --method PATCH `
    --uri "https://management.azure.com/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.ApiCenter/services/$apiCenterName`?api-version=2024-03-01" `
    --headers "Content-Type=application/json" `
    --body "@$($tempFile.FullName)" `
    --query "identity.principalId" -o tsv 2>&1
Remove-Item $tempFile.FullName

if ($LASTEXITCODE -eq 0 -and $apicIdentity) {
    Write-Ok "Managed identity: $apicIdentity"
} else {
    Write-Err "Failed to enable managed identity"
    exit 1
}

# ── Step 3: Grant APIM Service Reader role ──────────────────────────────────

Write-Step 3 "Granting APIM Service Reader role"

$apimId = "/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.ApiManagement/service/$apimName"

az role assignment create `
    --role "API Management Service Reader Role" `
    --assignee-object-id $apicIdentity `
    --assignee-principal-type ServicePrincipal `
    --scope $apimId -o none 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Ok "Role assigned: API Management Service Reader"
} else {
    Write-Info "Role may already be assigned (non-fatal)"
}

# ── Step 4: Create APIM integration ────────────────────────────────────────

Write-Step 4 "Creating APIM integration"

Write-Info "Installing apic-extension..."
az extension add --name apic-extension --allow-preview true 2>$null

$integrationResult = az apic integration create apim `
    --resource-group $rg `
    --service-name $apiCenterName `
    --integration-name apim-sync `
    --azure-apim $apimName 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Ok "Integration created: apim-sync"
} else {
    if ($integrationResult -match "already exists") {
        Write-Ok "Integration already exists: apim-sync"
    } else {
        Write-Err "Failed to create integration: $integrationResult"
        exit 1
    }
}

# ── Step 5: Verify sync ───────────────────────────────────────────────────

Write-Step 5 "Verifying sync"

Write-Info "Waiting 15s for sync to complete..."
Start-Sleep -Seconds 15

$state = az apic integration show `
    --resource-group $rg `
    --service-name $apiCenterName `
    --integration-name apim-sync `
    --query "linkState.state" -o tsv 2>&1

Write-Ok "Sync state: $state"

# List synced APIs
$apis = az rest --method GET `
    --uri "https://management.azure.com/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.ApiCenter/services/$apiCenterName/workspaces/default/apis?api-version=2024-03-01" `
    --query "value[].{title:properties.title, kind:properties.kind}" -o table 2>&1

Write-Host ""
Write-Host "  Synced APIs:" -ForegroundColor White
$apis | ForEach-Object { Write-Host "  $_" }

# ── Summary ─────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host ("=" * 65) -ForegroundColor Green
Write-Host "  API Center sync complete!" -ForegroundColor Green
Write-Host ("=" * 65) -ForegroundColor Green
Write-Host ""
Write-Host "  View in portal:" -ForegroundColor White
Write-Host "    Azure portal -> resource group '$rg' -> '$apiCenterName' -> Assets" -ForegroundColor Gray
Write-Host ""
