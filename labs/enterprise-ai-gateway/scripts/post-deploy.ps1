#Requires -Version 7.0
<#
.SYNOPSIS
    Post-deploy configuration for AI Gateway v2.
    Runs AFTER terraform apply + manual portal import of the Foundry API.

.DESCRIPTION
    This script bridges the gap between what Terraform can provision and what
    requires a portal-imported API to exist first:
      1. Reads terraform outputs for resource names, keys, endpoints
      2. Discovers the portal-imported API (path contains "openai")
      3. Grants APIM system identity RBAC on both Foundry accounts
      4. Associates the API with all three team products
      5. Configures API-level diagnostics (azuremonitor + applicationinsights)
      6. Applies the API-level policy XML (token metrics, backend pool, MI auth)
      7. Upgrades product policies from rate-limit-by-key to llm-token-limit
      8. Exports a .env file and prints shell env commands

.EXAMPLE
    .\scripts\post-deploy.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-Step {
    param([int]$Number, [string]$Title)
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  Step ${Number}: $Title" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "  ✓ $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "  → $Message" -ForegroundColor Yellow
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  ⚠ $Message" -ForegroundColor DarkYellow
}

function Invoke-AzRest {
    param(
        [string]$Method,
        [string]$Uri,
        [string]$Body
    )
    $azArgs = @("rest", "--method", $Method, "--url", $Uri)
    $tempFile = $null
    $responseFile = $null
    if ($Body) {
        # Write body to temp file to avoid shell escaping issues on Windows
        $tempFile = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.json'
        $Body | Set-Content -Path $tempFile -Encoding utf8NoBOM
        $azArgs += @("--body", "@$tempFile")
    }
    # Use --output-file to avoid BOM response parsing failures in az cli
    $responseFile = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '-resp.json'
    $azArgs += @("--output-file", $responseFile)
    try {
        $null = & az @azArgs 2>&1
        if ($LASTEXITCODE -ne 0) {
            $errContent = if (Test-Path $responseFile) { Get-Content $responseFile -Raw } else { "no response" }
            throw "az rest failed ($Method $Uri): exit=$LASTEXITCODE response=$errContent"
        }
        if ((Test-Path $responseFile) -and (Get-Item $responseFile).Length -gt 0) {
            $content = Get-Content $responseFile -Raw -Encoding utf8
            # Try to parse as JSON; if it's XML, just return null
            try { return $content | ConvertFrom-Json } catch { return $null }
        }
    }
    finally {
        if ($tempFile -and (Test-Path $tempFile)) {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }
        if ($responseFile -and (Test-Path $responseFile)) {
            Remove-Item $responseFile -Force -ErrorAction SilentlyContinue
        }
    }
}

# ── Step 0: Read terraform outputs ──────────────────────────────────────────

Write-Step 0 "Reading terraform outputs"

$tfDir = Join-Path $PSScriptRoot ".."
if (-not (Test-Path $tfDir)) {
    Write-Error "Terraform directory not found at: $tfDir"
    exit 1
}

Push-Location $tfDir
try {
    $tfRaw = terraform output -json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "terraform output failed. Have you run 'terraform apply'?"
        exit 1
    }
    $tf = $tfRaw | ConvertFrom-Json
}
finally {
    Pop-Location
}

$rg         = $tf.resource_group_name.value
$apimName   = $tf.apim_name.value
$gatewayUrl = $tf.apim_gateway_url.value
$foundryEus2Endpoint = $tf.foundry_primary_endpoint.value
$foundrySwcEndpoint  = $tf.foundry_secondary_endpoint.value

# Sensitive outputs — terraform output -json includes them
$alphaKey = $tf.team_alpha_subscription_key.value
$betaKey  = $tf.team_beta_subscription_key.value
$gammaKey = $tf.team_gamma_subscription_key.value

Write-Ok "Resource group: $rg"
Write-Ok "APIM name:      $apimName"
Write-Ok "Gateway URL:    $gatewayUrl"
Write-Ok "Foundry EUS2:   $foundryEus2Endpoint"
Write-Ok "Foundry SWC:    $foundrySwcEndpoint"

$apiVersion = "2024-05-01"

# Get APIM resource ID and system identity via az CLI (not in root TF outputs)
Write-Info "Fetching APIM resource details..."
$apimResource = az apim show -g $rg -n $apimName -o json 2>&1 | ConvertFrom-Json
$apimId = $apimResource.id
$systemPrincipalId = $apimResource.identity.principalId
Write-Ok "APIM ID:        $apimId"
Write-Ok "System MI:      $systemPrincipalId"

# App Insights logger ID (created by Terraform as 'app-insights-logger')
$aiLoggerId = "$apimId/loggers/app-insights-logger"
Write-Ok "AI Logger:      $aiLoggerId"

# Discover Foundry account IDs from the resource group
Write-Info "Discovering Foundry accounts..."
$foundryAccounts = az cognitiveservices account list -g $rg -o json 2>&1 | ConvertFrom-Json
$foundryEus2 = $foundryAccounts | Where-Object { $_.name -like "*eus2*" } | Select-Object -First 1
$foundrySwc  = $foundryAccounts | Where-Object { $_.name -like "*swc*" } | Select-Object -First 1

if (-not $foundryEus2 -or -not $foundrySwc) {
    Write-Error "Could not find both Foundry accounts in resource group $rg. Found: $($foundryAccounts | ForEach-Object { $_.name })"
    exit 1
}

$foundryEus2Id = $foundryEus2.id
$foundrySwcId  = $foundrySwc.id
Write-Ok "Foundry EUS2 ID: $foundryEus2Id"
Write-Ok "Foundry SWC ID:  $foundrySwcId"

# ── Step 1: Discover the portal-imported API ────────────────────────────────

Write-Step 1 "Discovering portal-imported API"

$apisRaw = az apim api list -g $rg -n $apimName -o json 2>&1
$allApis = $apisRaw | ConvertFrom-Json
$apis = @($allApis | Where-Object { $_.path -and $_.path -like "*openai*" })

if (-not $apis -or $apis.Count -eq 0) {
    Write-Error @"
No API with path containing 'openai' found in APIM '$apimName'.
Have you completed the manual portal import step?
  APIM → APIs → + Add API → Azure OpenAI Service → select Foundry endpoint
"@
    exit 1
}

# If multiple matches, prefer the portal-imported one (not the TF-created skeleton)
$api = if ($apis.Count -gt 1) {
    # The portal-imported one typically has a longer name or different displayName
    $imported = $apis | Where-Object { $_.displayName -ne "Chat Completions" } | Select-Object -First 1
    if ($imported) { $imported } else { $apis[0] }
} else {
    $apis[0]
}

$apiId   = $api.name  # This is the API's "name" field (used as ID in REST calls)
$apiName = $api.displayName
Write-Ok "Found API: '$apiName' (id: $apiId, path: /$($api.path))"

# Fix doubled path: the "Azure OpenAI" wizard sets the API path to "{base_path}/openai"
# (it appends /openai to whatever you entered). Fix it to just "openai".
if ($api.path -ne "openai") {
    Write-Info "Fixing API path from '/$($api.path)' to '/openai'..."
    $null = az apim api update -g $rg -n $apimName --api-id $apiId --set path=openai --only-show-errors 2>&1
    Write-Ok "API path corrected to /openai"
} else {
    Write-Ok "API path is already /openai"
}

# Add wildcard POST operation for v1 paths (/v1/chat/completions, etc.)
# The wizard only creates deployment-based operations (/deployments/{id}/...).
# The wildcard lets APIM route v1 requests to the backend pool.
Write-Info "Adding wildcard POST operation for v1 path support..."
$wildcardBody = @{
    properties = @{
        displayName = "Wildcard POST"
        method = "POST"
        urlTemplate = "/{*path}"
        description = "Pass-through for v1 and other POST paths"
        templateParameters = @(
            @{
                name = "path"
                type = "string"
                required = $true
            }
        )
    }
} | ConvertTo-Json -Depth 4

Invoke-AzRest -Method PUT `
    -Uri "https://management.azure.com$apimId/apis/$apiId/operations/wildcard-post?api-version=$apiVersion" `
    -Body $wildcardBody

Write-Ok "Wildcard POST operation added"

# ── Step 2: Grant APIM system identity RBAC on both Foundry accounts ───────

Write-Step 2 "Granting APIM system identity RBAC on Foundry accounts"

$rbacRole = "Cognitive Services OpenAI User"

# EUS2 — may already exist from portal import wizard
Write-Info "Assigning '$rbacRole' on EUS2 Foundry..."
$eus2Result = az role assignment create `
    --assignee $systemPrincipalId `
    --role $rbacRole `
    --scope $foundryEus2Id `
    --only-show-errors 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Ok "EUS2 RBAC assignment OK (created or already existed)"
} else {
    if ($eus2Result -match "already exists") {
        Write-Ok "EUS2 RBAC assignment already exists"
    } else {
        Write-Warn "EUS2 RBAC assignment may have failed: $eus2Result"
    }
}

# SWC — this one is almost always missing (the portal only imports from one account)
Write-Info "Assigning '$rbacRole' on SWC Foundry..."
$swcResult = az role assignment create `
    --assignee $systemPrincipalId `
    --role $rbacRole `
    --scope $foundrySwcId `
    --only-show-errors 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Ok "SWC RBAC assignment OK (created or already existed)"
} else {
    if ($swcResult -match "already exists") {
        Write-Ok "SWC RBAC assignment already exists"
    } else {
        Write-Warn "SWC RBAC assignment may have failed: $swcResult"
    }
}

# ── Step 3: Associate API with all 3 products ──────────────────────────────

Write-Step 3 "Associating API with team products"

$products = @("team-alpha", "team-beta", "team-gamma")

foreach ($productId in $products) {
    Write-Info "Adding API '$apiId' to product '$productId'..."
    $addResult = az apim product api add `
        -g $rg `
        -n $apimName `
        --product-id $productId `
        --api-id $apiId `
        --only-show-errors 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Ok "$productId ← $apiId"
    } else {
        if ($addResult -match "already exists" -or $addResult -match "ApiAlreadyAdded") {
            Write-Ok "$productId ← $apiId (already linked)"
        } else {
            Write-Warn "Failed to add API to $productId`: $addResult"
        }
    }
}

# ── Step 4: Configure API-level diagnostics ─────────────────────────────────

Write-Step 4 "Configuring API-level diagnostics"

# 4a: Azure Monitor diagnostic — turns on LLM log generation for this API
# This is the "faucet" that makes GatewayLlmLogs flow (improvement #26)
Write-Info "Configuring azuremonitor diagnostic (LLM log generation)..."

$azMonBody = @{
    properties = @{
        loggerId = "$apimId/loggers/azuremonitor"
        logClientIp = $true
        sampling = @{
            samplingType = "fixed"
            percentage = 100
        }
        largeLanguageModel = @{
            logs = "enabled"
        }
    }
} | ConvertTo-Json -Depth 5

Invoke-AzRest -Method PUT `
    -Uri "https://management.azure.com$apimId/apis/$apiId/diagnostics/azuremonitor?api-version=$apiVersion" `
    -Body $azMonBody

Write-Ok "azuremonitor diagnostic: LLM logs enabled"

# 4b: Application Insights diagnostic — routes llm-emit-token-metric to customMetrics
# Without this, the llm-emit-token-metric policy data goes nowhere (improvement #29)
Write-Info "Configuring applicationinsights diagnostic (custom metrics)..."

$aiBody = @{
    properties = @{
        loggerId = $aiLoggerId
        logClientIp = $true
        sampling = @{
            samplingType = "fixed"
            percentage = 100
        }
        metrics = $true
    }
} | ConvertTo-Json -Depth 5

Invoke-AzRest -Method PUT `
    -Uri "https://management.azure.com$apimId/apis/$apiId/diagnostics/applicationinsights?api-version=$apiVersion" `
    -Body $aiBody

Write-Ok "applicationinsights diagnostic: metrics enabled → App Insights"

# ── Step 5: Apply API-level policy XML ──────────────────────────────────────

Write-Step 5 "Applying API-level policy"

$policyFile = Join-Path $PSScriptRoot "..\policies\api-policy.xml"
if (-not (Test-Path $policyFile)) {
    Write-Error "Policy file not found: $policyFile"
    exit 1
}

$policyXml = Get-Content -Path $policyFile -Raw
Write-Info "Loaded policy from: $policyFile"

# Escape the XML for JSON embedding
$policyJsonValue = $policyXml | ConvertTo-Json

$policyBody = @"
{
    "properties": {
        "format": "xml",
        "value": $policyJsonValue
    }
}
"@

Invoke-AzRest -Method PUT `
    -Uri "https://management.azure.com$apimId/apis/$apiId/policies/policy?api-version=$apiVersion" `
    -Body $policyBody

Write-Ok "API policy applied: llm-emit-token-metric + set-backend-service + MI auth"

# ── Step 6: Upgrade product policies to llm-token-limit ─────────────────────

Write-Step 6 "Upgrading product policies to llm-token-limit"

$productPolicies = @(
    @{ Id = "team-alpha"; TPM = 50000; Label = "Alpha (50K TPM)" }
    @{ Id = "team-beta";  TPM = 20000; Label = "Beta (20K TPM)" }
    @{ Id = "team-gamma"; TPM = 500;   Label = "Gamma (500 TPM)" }
)

foreach ($product in $productPolicies) {
    Write-Info "Setting $($product.Label)..."

    $productPolicyXml = @"
<policies>
    <inbound>
        <base />
        <llm-token-limit
            tokens-per-minute="$($product.TPM)"
            counter-key="@(context.Subscription.Id)"
            estimate-prompt-tokens="false" />
    </inbound>
    <backend><base /></backend>
    <outbound><base /></outbound>
    <on-error><base /></on-error>
</policies>
"@

    $productPolicyJsonValue = $productPolicyXml | ConvertTo-Json

    $productPolicyBody = @"
{
    "properties": {
        "format": "xml",
        "value": $productPolicyJsonValue
    }
}
"@

    Invoke-AzRest -Method PUT `
        -Uri "https://management.azure.com$apimId/products/$($product.Id)/policies/policy?api-version=$apiVersion" `
        -Body $productPolicyBody

    Write-Ok "$($product.Label) → llm-token-limit applied"
}

# ── Step 7: Export environment variables ────────────────────────────────────

Write-Step 7 "Exporting environment variables"

# Build the v1 base URL: gateway + /openai/v1
$baseUrl = "$gatewayUrl/openai/v1"

$envVars = [ordered]@{
    AIGW_GATEWAY_URL            = $gatewayUrl
    AIGW_BASE_URL               = $baseUrl
    AIGW_APIM_NAME              = $apimName
    AIGW_RESOURCE_GROUP         = $rg
    AIGW_API_ID                 = $apiId
    AIGW_ALPHA_KEY              = $alphaKey
    AIGW_BETA_KEY               = $betaKey
    AIGW_GAMMA_KEY              = $gammaKey
    AIGW_FOUNDRY_EUS2_ENDPOINT  = $foundryEus2Endpoint
    AIGW_FOUNDRY_SWC_ENDPOINT   = $foundrySwcEndpoint
}

# Write .env file in project root
$envFile = Join-Path $PSScriptRoot "..\.env"
$envLines = $envVars.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
$envLines | Set-Content -Path $envFile -Encoding utf8
Write-Ok "Written to: $envFile"

# Print PowerShell export commands
Write-Host ""
Write-Host "  PowerShell:" -ForegroundColor Magenta
foreach ($kv in $envVars.GetEnumerator()) {
    Write-Host "    `$env:$($kv.Key) = `"$($kv.Value)`""
}

# Print cmd.exe export commands
Write-Host ""
Write-Host "  cmd.exe:" -ForegroundColor Magenta
foreach ($kv in $envVars.GetEnumerator()) {
    Write-Host "    set $($kv.Key)=$($kv.Value)"
}

# Also set them in the current PowerShell session
foreach ($kv in $envVars.GetEnumerator()) {
    [System.Environment]::SetEnvironmentVariable($kv.Key, $kv.Value, "Process")
}
Write-Ok "Environment variables set in current session"

# ── Done ─────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "  Post-deploy complete!" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "  Verify in portal:" -ForegroundColor White
Write-Host "    1. APIM → APIs → '$apiName' should show the policy XML" -ForegroundColor Gray
Write-Host "    2. APIM → APIs → Settings → Diagnostic Logs → Azure Monitor → LLM = Enabled" -ForegroundColor Gray
Write-Host "    3. APIM → Products → each team → Policies → llm-token-limit visible" -ForegroundColor Gray
Write-Host ""
Write-Host "  Quick test:" -ForegroundColor White
Write-Host "    python -c `"" -ForegroundColor Gray -NoNewline
Write-Host "from openai import OpenAI; c = OpenAI(base_url='$baseUrl', api_key='$alphaKey', default_headers={'api-key': '$alphaKey'}); print(c.chat.completions.create(model='gpt-51', messages=[{'role':'user','content':'hi'}], max_completion_tokens=50).choices[0].message.content)" -ForegroundColor Gray -NoNewline
Write-Host "`"" -ForegroundColor Gray
Write-Host ""
