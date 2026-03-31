<#
.SYNOPSIS
    Reads terraform outputs and exports AI Gateway environment variables.

.DESCRIPTION
    Dot-source this script to populate your session with the env vars
    that the test scripts expect:
        . .\set_env.ps1

    Reads from infra/terraform via 'terraform output -raw'.
#>

$ErrorActionPreference = "Stop"

$tfDir = Join-Path $PSScriptRoot ".." "infra" "terraform"
if (-not (Test-Path $tfDir)) {
    Write-Error "Terraform directory not found: $tfDir"
    return
}

Push-Location $tfDir
try {
    Write-Host "Reading terraform outputs from $tfDir ..." -ForegroundColor Cyan

    $gatewayUrl      = terraform output -raw apim_gateway_url
    $alphaKey        = terraform output -raw team_alpha_subscription_key
    $betaKey         = terraform output -raw team_beta_subscription_key
    $gammaKey        = terraform output -raw team_gamma_subscription_key
    $resourceGroup   = terraform output -raw resource_group_name
    $foundryEus2Name = terraform output -raw apim_name   # used to derive foundry name

    # The gateway URL from terraform is the base APIM URL (https://NAME.azure-api.net).
    # Tests expect the unified v1 path appended.
    $env:AIGW_GATEWAY_URL    = "$gatewayUrl/openai/v1"
    $env:AIGW_ALPHA_KEY      = $alphaKey
    $env:AIGW_BETA_KEY       = $betaKey
    $env:AIGW_GAMMA_KEY      = $gammaKey
    $env:AIGW_RESOURCE_GROUP = $resourceGroup

    # Foundry account name for eus2 (used by test5_failover for az cli scale commands).
    # Terraform outputs the endpoint; derive the account name from it, or read directly.
    try {
        $foundryEus2Endpoint = terraform output -raw foundry_primary_endpoint
        # Endpoint is like https://NAME.cognitiveservices.azure.com — extract NAME
        $env:AIGW_FOUNDRY_EUS2 = ([Uri]$foundryEus2Endpoint).Host.Split('.')[0]
        # Also set the project-level endpoint for test9_foundry_agent
        $foundryName = $env:AIGW_FOUNDRY_EUS2
        $projectName = $foundryName -replace 'foundry', 'project'
        $env:AZURE_FOUNDRY_ENDPOINT = "https://$foundryName.services.ai.azure.com/api/projects/$projectName"
    } catch {
        Write-Warning "Could not read foundry_primary_endpoint. Set AIGW_FOUNDRY_EUS2 manually for test5."
    }

    # MCP Demo (Phase 2)
    # MCP tests use the base gateway URL (without /openai/v1 path)
    try {
        $mcpKey = terraform output -raw mcp_demo_subscription_key
        $env:AIGW_MCP_KEY = $mcpKey
        $env:AIGW_MCP_URL = "$gatewayUrl/learn/mcp"
    } catch {
        # MCP not enabled — tests will skip
    }

    Write-Host ""
    Write-Host "Environment variables set:" -ForegroundColor Green
    Write-Host "  AIGW_GATEWAY_URL         = $env:AIGW_GATEWAY_URL"
    Write-Host "  AIGW_ALPHA_KEY           = $($env:AIGW_ALPHA_KEY.Substring(0,8))..."
    Write-Host "  AIGW_BETA_KEY            = $($env:AIGW_BETA_KEY.Substring(0,8))..."
    Write-Host "  AIGW_GAMMA_KEY           = $($env:AIGW_GAMMA_KEY.Substring(0,8))..."
    Write-Host "  AIGW_RESOURCE_GROUP      = $env:AIGW_RESOURCE_GROUP"
    Write-Host "  AIGW_FOUNDRY_EUS2        = $env:AIGW_FOUNDRY_EUS2"
    Write-Host "  AZURE_FOUNDRY_ENDPOINT   = $env:AZURE_FOUNDRY_ENDPOINT"
    if ($env:AIGW_MCP_KEY) {
        Write-Host "  AIGW_MCP_KEY             = $($env:AIGW_MCP_KEY.Substring(0,8))..."
        Write-Host "  AIGW_MCP_URL             = $env:AIGW_MCP_URL"
    } else {
        Write-Host "  AIGW_MCP_KEY             = (not set - MCP tests will be skipped)" -ForegroundColor Yellow
    }
} finally {
    Pop-Location
}
