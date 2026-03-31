#Requires -Version 7.0
<#
.SYNOPSIS
    Post-portal setup for MCP governance demo.
    Run AFTER registering the MCP server in the APIM portal.

.DESCRIPTION
    The MCP server must be registered manually in the portal first
    (APIM -> APIs -> MCP Servers -> + Create). This script handles
    everything else:

      1. Reads terraform outputs
      2. Fixes the backend URL (known APIM issue)
      3. Associates MCP server with the mcp-servers product
      4. Verifies MCP server connectivity through APIM
      5. Prints env vars for running MCP tests

    Policy application is also portal-only — the script prints
    instructions for that step.

.EXAMPLE
    .\setup-mcp-demo.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-Step {
    param([int]$Number, [string]$Title)
    Write-Host ""
    Write-Host ("=" * 65) -ForegroundColor Cyan
    Write-Host "  Step ${Number}: $Title" -ForegroundColor Cyan
    Write-Host ("=" * 65) -ForegroundColor Cyan
}

function Write-Ok    { param([string]$M) Write-Host "  [OK] $M" -ForegroundColor Green }
function Write-Info  { param([string]$M) Write-Host "  $M" -ForegroundColor Yellow }
function Write-Err   { param([string]$M) Write-Host "  [FAIL] $M" -ForegroundColor Red }

# ── Step 1: Read terraform outputs ──────────────────────────────────────────

Write-Step 1 "Reading terraform outputs"

$tfDir = Join-Path $PSScriptRoot "..\infra\terraform"
Push-Location $tfDir
try {
    $tf = terraform output -json 2>&1 | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw "terraform output failed" }
} finally { Pop-Location }

$rg         = $tf.resource_group_name.value
$apimName   = $tf.apim_name.value
$gatewayUrl = $tf.apim_gateway_url.value
$subId      = (az account show --query id -o tsv).Trim()
$mcpKey     = $null
if ($tf.PSObject.Properties["mcp_demo_subscription_key"]) {
    $mcpKey = $tf.mcp_demo_subscription_key.value
}

Write-Ok "Resource group : $rg"
Write-Ok "APIM           : $apimName"
Write-Ok "Gateway URL    : $gatewayUrl"
Write-Ok "Subscription   : $subId"
if ($mcpKey) { Write-Ok "MCP key        : $($mcpKey.Substring(0,4))****" }

# ── Step 2: Check MCP server exists ─────────────────────────────────────────

Write-Step 2 "Checking MCP server registration"

$mcpServerName = "microsoft-learn"
$apiVersion = "2024-05-01"

# az apim api list doesn't show MCP-type APIs - must use REST with preview version
$apisJson = az rest --method GET `
    --uri "https://management.azure.com/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.ApiManagement/service/$apimName/apis?api-version=2025-03-01-preview" `
    --query "value[].name" -o tsv 2>&1
if ($apisJson -match $mcpServerName) {
    Write-Ok "MCP server '$mcpServerName' found in APIM"
} else {
    Write-Err "MCP server '$mcpServerName' not found in APIM"
    Write-Host ""
    Write-Info "Complete QUICKSTART Step 7a (portal registration) first, then re-run this script."
    exit 1
}

# ── Step 3: Fix backend URL ─────────────────────────────────────────────────

Write-Step 3 "Fixing backend URL (known APIM issue)"

Write-Info "APIM sets the backend to learn.microsoft.com instead of learn.microsoft.com/api"
Write-Info "This causes 403s. Fixing..."

# Find the MCP backend
$backendsJson = az rest --method GET `
    --uri "https://management.azure.com/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.ApiManagement/service/$apimName/backends?api-version=$apiVersion" `
    -o json 2>&1
$backends = $backendsJson | ConvertFrom-Json
$mcpBackend = $backends.value | Where-Object { $_.name -match "microsoft-learn" }

if ($mcpBackend) {
    $currentUrl = $mcpBackend.properties.url
    Write-Info "Current backend URL: $currentUrl"

    if ($currentUrl -eq "https://learn.microsoft.com/api") {
        Write-Ok "Backend URL already correct - no fix needed"
    } else {
        # Fix it
        $tempFile = New-TemporaryFile
        '{"properties":{"url":"https://learn.microsoft.com/api","protocol":"http"}}' | Set-Content $tempFile.FullName
        az rest --method PATCH `
            --uri "https://management.azure.com/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.ApiManagement/service/$apimName/backends/$($mcpBackend.name)?api-version=$apiVersion" `
            --headers "Content-Type=application/json" `
            --body "@$($tempFile.FullName)" -o none 2>&1
        Remove-Item $tempFile.FullName
        Write-Ok "Backend URL fixed: $currentUrl -> https://learn.microsoft.com/api"
        Write-Info "Waiting 15s for change to propagate..."
        Start-Sleep -Seconds 15
    }
} else {
    Write-Err "Could not find MCP backend - the backend URL may need manual fixing"
    Write-Info "Check APIM -> Backends in the portal"
}

# ── Step 4: Associate with product ──────────────────────────────────────────

Write-Step 4 "Associating MCP server with product"

$mcpProductId = "mcp-servers"
try {
    $addResult = az apim product api add -g $rg -n $apimName --product-id $mcpProductId --api-id $mcpServerName --only-show-errors 2>&1
    if ($LASTEXITCODE -eq 0 -or $addResult -match "already exists|ApiAlreadyAdded") {
        Write-Ok "$mcpProductId <- $mcpServerName"
    } else {
        throw $addResult
    }
} catch {
    Write-Info "Product association skipped (may already be linked from portal registration)"
}

# ── Step 5: Verify connectivity ─────────────────────────────────────────────

Write-Step 5 "Verifying MCP server connectivity"

$mcpEndpoint = "$gatewayUrl/learn/mcp"
Write-Info "Testing: POST $mcpEndpoint"

try {
    $headers = @{
        "Content-Type" = "application/json"
        "Accept" = "application/json, text/event-stream"
        "Mcp-Session-Id" = "setup-verify-$(Get-Random)"
    }
    if ($mcpKey) { $headers["Ocp-Apim-Subscription-Key"] = $mcpKey }

    $body = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"setup-verify","version":"1.0"}}}'

    $resp = Invoke-WebRequest -Uri $mcpEndpoint -Method POST -Headers $headers -Body $body -ErrorAction Stop
    
    if ($resp.StatusCode -eq 200) {
        Write-Ok "MCP server responded: HTTP 200"
        $contentType = $resp.Headers["Content-Type"]
        if ($contentType -match "event-stream") {
            Write-Ok "Content-Type: $contentType (SSE - correct)"
        }
        # Check for tool names in response
        $content = $resp.Content
        if ($content -match "microsoft_docs_search") {
            Write-Ok "Tools detected: microsoft_docs_search"
        }
    } else {
        Write-Err "Unexpected status: $($resp.StatusCode)"
    }
} catch {
    $errMsg = $_.Exception.Message
    if ($errMsg -match "403") {
        Write-Err "Got 403 - backend URL fix may not have taken effect yet"
        Write-Info "Wait 30 seconds and re-run, or check APIM -> Backends in portal"
    } elseif ($errMsg -match "401") {
        Write-Err "Got 401 - subscription key may be invalid"
        Write-Info "Check that the MCP product subscription key is correct"
    } else {
        Write-Err "Connectivity test failed: $errMsg"
    }
}

# ── Summary ─────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host ("=" * 65) -ForegroundColor Green
Write-Host "  Setup complete!" -ForegroundColor Green
Write-Host ("=" * 65) -ForegroundColor Green
Write-Host ""
Write-Host "  MCP endpoint : $mcpEndpoint" -ForegroundColor White
if ($mcpKey) {
    Write-Host "  MCP key      : $($mcpKey.Substring(0,4))****" -ForegroundColor White
}
Write-Host ""
Write-Host "  Run MCP tests:" -ForegroundColor White
Write-Host "    python tests/test_mcp_governance.py" -ForegroundColor Gray
Write-Host "    python tests/test_mcp_rate_limit.py" -ForegroundColor Gray
Write-Host ""

# Export env vars for MCP tests
$env:AIGW_MCP_KEY = $mcpKey
$env:AIGW_MCP_URL = $mcpEndpoint
Write-Ok "Set AIGW_MCP_KEY and AIGW_MCP_URL in current session"
