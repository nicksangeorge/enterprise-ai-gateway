# MCP Tool Governance — End-to-End Validation

Full rebuild validation from a clean Azure subscription. Covers Phase 1 (LLM gateway) + Phase 2 (MCP governance).

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Terraform | >= 1.5 | `winget install Hashicorp.Terraform` |
| Azure CLI | Latest | `winget install Microsoft.AzureCLI` |
| Python | >= 3.10 | `winget install Python.Python.3.12` |
| PowerShell 7 | >= 7.0 | `winget install Microsoft.PowerShell` |

> **PowerShell 7 required.** The scripts use PowerShell 7+ syntax. Check your version with `$PSVersionTable.PSVersion`. If you're on 5.x (Windows PowerShell), install 7 with `winget install Microsoft.PowerShell` and reopen your terminal as `pwsh`.

You need **Contributor** and **User Access Administrator** roles on the target subscription.

```powershell
az login
az account set --subscription "<your-subscription-id>"
```

Budget ~25 minutes for the full deploy + validation.

## Step 0: Clean slate

Verify no existing resources from a previous deploy:

```powershell
az group show -n rg-ai-gateway-demo 2>&1
# Expected: "... could not be found." or similar "not found" error
```

If the resource group exists, destroy it first. Portal-imported APIs and stray workbooks block `terraform destroy`, so clean them manually:

```powershell
cd infra/terraform

# Get resource names (skip if you know them)
$apimName = terraform output -raw apim_name
$rg = terraform output -raw resource_group_name
$subId = (az account show --query id -o tsv)

# Delete API diagnostics (blocks API deletion)
az rest --method DELETE --uri "https://management.azure.com/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.ApiManagement/service/$apimName/apis/foundry-ai-gateway/diagnostics/applicationinsights?api-version=2024-05-01"
az rest --method DELETE --uri "https://management.azure.com/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.ApiManagement/service/$apimName/apis/foundry-ai-gateway/diagnostics/azuremonitor?api-version=2024-05-01"

# Delete the portal-imported API
az apim api delete -g $rg -n $apimName --api-id foundry-ai-gateway --delete-revisions true -y

# Delete stray workbooks (another common blocker)
az resource list -g $rg --query "[?type=='Microsoft.Insights/workbooks'].id" -o tsv | ForEach-Object { az resource delete --ids $_ }

# Now destroy will work
terraform destroy -auto-approve
```

After destroy, purge Foundry soft-deletes if redeploying with the same prefix:

```powershell
# Use the actual account names from your previous deploy
az cognitiveservices account purge --name aigw-foundry-eus2-xxxx --resource-group rg-ai-gateway-demo --location eastus2
az cognitiveservices account purge --name aigw-foundry-swc-xxxx --resource-group rg-ai-gateway-demo --location swedencentral
```

## Step 1: Terraform apply (~15 min)

```powershell
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set subscription_id at minimum
```

Deploy with MCP demo enabled:

```powershell
terraform init

# Create a tfvars file (avoids PowerShell quoting issues with -var flags):
@'
enable_mcp_demo  = true
mcp_server_url   = "https://learn.microsoft.com/api/mcp"
'@ | Set-Content -Path "mcp-demo.auto.tfvars"

terraform plan -out deploy.tfplan
terraform apply deploy.tfplan
```

APIM Standard v2 is the bottleneck (5-10 min). Everything else finishes in 1-3 min.

**Expected outputs** (verify after apply):

```powershell
terraform output apim_name
# → aigw-apim-xxxx (your random suffix)

terraform output apim_gateway_url
# → https://aigw-apim-xxxx.azure-api.net

terraform output mcp_demo_subscription_key
# → (32-char hex key)

terraform output resource_group_name
# → rg-ai-gateway-demo
```

All 11 outputs should be present: `resource_group_name`, `apim_gateway_url`, `apim_name`, `foundry_primary_endpoint`, `foundry_secondary_endpoint`, `app_insights_connection_string`, `team_alpha_subscription_key`, `team_beta_subscription_key`, `team_gamma_subscription_key`, `backend_pool_name`, `mcp_demo_subscription_key`.

## Step 2: Deploy Kimi-K2.5 (optional, ~3 min)

Skip this if you only need GPT-5.1 and Model Router.

1. Go to [ai.azure.com](https://ai.azure.com) → Model catalog → search "Kimi-K2.5"
2. Deploy as Global Standard to your primary Foundry account (e.g., `aigw-foundry-eus2-xxxx`). Deployment name: `kimi-k25`
3. Repeat for the secondary account (e.g., `aigw-foundry-swc-xxxx`)

## Step 3: Import Foundry API in APIM (~2 min)

This is a manual portal step. No known CLI or IaC equivalent replicates what the wizard does.

1. Azure portal → your APIM instance → APIs → **+ Add API**
2. Under "Create an AI API", click **Microsoft Foundry**
3. On the "Select AI Service" tab, pick your primary Foundry account (e.g., `aigw-foundry-eus2-xxxx`)
4. On the "Configure API" tab:

   | Field | Value |
   |-------|-------|
   | Display name | `Foundry AI Gateway` |
   | Name | `foundry-ai-gateway` (auto-fills) |
   | Base path | `openai` |
   | Products | Leave blank (post-deploy script handles this) |

5. Under **Client compatibility**, select **Azure OpenAI**. Do not select "Azure AI" or "Azure OpenAI v1" (doubles the path).
6. Skip the remaining tabs. Click **Review** → **Create**.

**Verify:**

```powershell
$apimName = terraform output -raw apim_name
az apim api list -g rg-ai-gateway-demo -n $apimName --query "[].{name:name, path:path}" -o table
```

Expected:

```
Name                  Path
--------------------  ------
foundry-ai-gateway    openai
```

## Step 4: Run Phase 1 post-deploy script (~3 min)

```powershell
cd scripts
.\post-deploy.ps1
```

The script reads terraform outputs and configures:
- Fixes the API path if the wizard doubled it (`openai/openai` → `openai`)
- Adds a wildcard POST operation for v1 path routing
- Grants APIM system identity RBAC on both Foundry accounts
- Associates the API with all three team products
- Configures API-level diagnostics (Azure Monitor LLM logs + App Insights metrics)
- Applies the API-level policy (token metrics, backend pool, managed identity auth)
- Upgrades product policies from `rate-limit-by-key` to `llm-token-limit`
- Exports a `.env` file and prints shell env commands

**Expected:** Each step prints ✓ in green. Script ends with "Post-deploy complete!"

## Step 5: Validate Phase 1 baseline

Load environment variables and install test dependencies:

```powershell
cd scripts
. .\set_env.ps1
pip install -r ..\tests\requirements.txt
```

Run the Phase 1 test suite:

```powershell
.\run_tests.ps1
```

**Expected:** 7 tests run in sequence:

| Test | What it checks |
|------|---------------|
| test1_connectivity | Basic APIM → Foundry round-trip |
| test2_model_router | Model Router resolves `gpt-51` |
| test3_load | Concurrent requests succeed |
| test4_quota | Token quota enforcement (Gamma 500 TPM) |
| test5_failover | Circuit breaker failover (may need `-SkipFailover`) |
| test6_metrics | App Insights `customMetrics` populated |
| test7_llm_logs | `ApiManagementGatewayLlmLog` entries appear |

Tests 6-7 poll with backoff because Log Analytics ingestion takes 2-10 min. If they time out on a fresh deploy, re-run after a few minutes.

**Quick smoke test** (if you want to verify before running the full suite):

```powershell
$url = terraform output -raw apim_gateway_url
$key = terraform output -raw team_alpha_subscription_key
$body = '{"model":"gpt-51","messages":[{"role":"user","content":"Say hello"}],"max_completion_tokens":20}'
Invoke-RestMethod -Uri "$url/openai/v1/chat/completions" -Method POST -Headers @{"api-key"=$key; "Content-Type"="application/json"} -Body $body
```

Expected: JSON response with `choices[0].message.content` containing a greeting.

## Step 6: Register MCP server in APIM (manual, ~3 min)

> **Note:** MCP server registration is portal-only as of March 2026. The `mcpServers` REST API is not yet available on any ARM API version for StandardV2. The `setup-mcp-demo.ps1` script will attempt automation but will fall back to manual instructions.

### 6a: Register MCP server in portal

1. Azure portal → APIM (`aigw-apim-xxxx`) → **APIs** → **MCP Servers** → **+ Create MCP server**
2. Select **Expose an existing MCP server**
3. Fill in:

| Field | Value |
|---|---|
| **MCP server base URL** | `https://learn.microsoft.com/api/mcp` |
| **Transport type** | Streamable HTTP |
| **Name** | `microsoft-learn` |
| **Base path** | `learn` |
| **Products** | Check **MCP Servers - Governed Tools** |

4. Click **Create**

### 6b: Fix backend URL (known issue)

APIM may split the base URL incorrectly, setting the backend to `https://learn.microsoft.com` instead of `https://learn.microsoft.com/api`. This causes 403s from Learn's CDN. Fix it:

```powershell
$subId = (az account show --query id -o tsv)
$rg = (cd infra\terraform && terraform output -raw resource_group_name)
$apimName = (cd infra\terraform && terraform output -raw apim_name)

# Find the MCP backend name
$backendName = az rest --method GET --uri "https://management.azure.com/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.ApiManagement/service/$apimName/backends?api-version=2024-05-01" --query "value[?contains(name,'microsoft-learn')].name" -o tsv

# Fix the URL
$tempFile = New-TemporaryFile
'{"properties":{"url":"https://learn.microsoft.com/api","protocol":"http"}}' | Set-Content $tempFile.FullName
az rest --method PATCH --uri "https://management.azure.com/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.ApiManagement/service/$apimName/backends/$($backendName)?api-version=2024-05-01" --headers "Content-Type=application/json" --body "@$($tempFile.FullName)" -o none
Remove-Item $tempFile.FullName
```

### 6c: Verify MCP server works

```powershell
$url = (cd infra\terraform && terraform output -raw apim_gateway_url)
$key = (cd infra\terraform && terraform output -raw mcp_demo_subscription_key)

Invoke-WebRequest -Uri "$url/learn/mcp" -Method POST -Headers @{
    "Content-Type"="application/json"
    "Accept"="application/json, text/event-stream"
    "Ocp-Apim-Subscription-Key"=$key
    "Mcp-Session-Id"="test-1"
} -Body '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
```

**Expected:** Status 200, Content-Type `text/event-stream`, body contains `Microsoft Learn MCP Server` with tools like `microsoft_docs_search`.

### 6d: Apply governance policy (optional — enhances rate limiting)

In the portal: APIM → APIs → MCP Servers → `microsoft-learn` → MCP → Policies → paste the contents of `infra/terraform/modules/apim-config/policies/mcp-governance.xml` → Save.

Or run the setup script for the remaining steps:

```powershell
cd scripts
.\setup-mcp-demo.ps1
```

The script will skip the MCP registration (already done) and attempt policy application + API Center linking.

## Step 7: Validate MCP governance

Set environment variables:

```powershell
cd infra\terraform
$env:AIGW_GATEWAY_URL = terraform output -raw apim_gateway_url
$env:AIGW_MCP_KEY = terraform output -raw mcp_demo_subscription_key
```

Then navigate to tests and run:

```powershell
cd ..\..\tests
python test_mcp_governance.py
```

**Expected output:**

```
============================================================
MCP Governance Tests
============================================================
Gateway: https://aigw-apim-xxxx.azure-api.net
MCP URL: https://aigw-apim-xxxx.azure-api.net/learn/mcp

✅ connectivity: tools/list returned 200
✅ correlation-id: <uuid>
✅ tools-list: N tools returned
✅ independent-counters: 5 calls + 5 lists all passed (same session)

------------------------------------------------------------
Results: 4 passed, 0 failed, 4 total
```

Run the rate limit tests (4 tests):

```powershell
python test_mcp_rate_limit.py
```

**Expected output:**

```
============================================================
MCP Rate Limit Tests
============================================================
--- tools/call rate limit ---
  Sending 15 tools/call requests (limit: 10/60s) ...
  [ 1] 200
  ...
  [11] 429 — rate limited
  ...
✅ tools/call rate limit: 429 started at request #11 (10 passed, 5 blocked)

--- tools/list rate limit ---
  Sending 65 tools/list requests (limit: 60/60s) ...
  ...
✅ tools/list rate limit: 429 started at request #61 (60 passed, 5 blocked)

--- session isolation ---
✅ session isolation: A is limited, B passed all 5 requests

--- retry-after header ---
✅ retry-after: 429 response includes Retry-After: <N>s

============================================================
Results: 4 passed, 0 failed, 4 total
```

The 429 thresholds are:
- `tools/call`: 10 requests per 60 seconds per session
- `tools/list`: 60 requests per 60 seconds per session

If you re-run rate limit tests within 60 seconds of the previous run, the counters may not have reset. Wait a minute between runs.

## Step 8: Run Foundry agent demo

Install dependencies:

```powershell
cd demo
pip install -r requirements.txt
```

Set environment variables:

```powershell
cd ..\infra\terraform
$env:AZURE_FOUNDRY_ENDPOINT = terraform output -raw foundry_primary_endpoint
$env:AIGW_GATEWAY_URL = terraform output -raw apim_gateway_url
$env:AIGW_MCP_KEY = terraform output -raw mcp_demo_subscription_key
cd ..\..\demo
```

> **Note:** The endpoint from terraform may be the `.cognitiveservices.azure.com` format. The v2 agent API needs the project-level endpoint: `https://<account>.services.ai.azure.com/api/projects/<project-name>`. If the script warns about a missing `/api/projects/` path, set it manually:
> ```powershell
> $env:AZURE_FOUNDRY_ENDPOINT = "https://aigw-foundry-eus2-xxxx.services.ai.azure.com/api/projects/aigw-project-eus2-xxxx"
> ```

Run the demo:

```powershell
python foundry-agent-demo.py
```

**What it does:**
1. Connects to Foundry via `AIProjectClient`
2. Creates a v2 prompt agent with an MCP tool pointing at APIM (not the raw MCP server)
3. Invokes the agent — the agent calls the MCP tool, which routes through APIM
4. Displays tool call evidence and the agent's response
5. Runs a multi-turn follow-up query

**Expected output:**

```
  ✅ Agent created: learn-search-agent (version 1)
  🔧 MCP tool calls detected: 2
    → [learn_search] microsoft_docs_search
  ✅ Tool calls routed through APIM gateway
```

**Cleanup:** The agent persists after the script runs. To delete it:

```powershell
python cleanup-agent.py                    # delete learn-search-agent (all versions)
python cleanup-agent.py --list             # list all agents in the project
python cleanup-agent.py --name X --version 1  # delete specific version
```

**If the demo fails:**
- Verify `az login` is current and the correct subscription is selected
- Check that `gpt-51` (or your chosen model) is deployed in the Foundry project
- Ensure the MCP server is registered in APIM and the governance policy is applied (Step 6)
- Check SDK version: `pip show azure-ai-projects` (needs >= 2.0.0)

## Step 9: Configure API Center sync

API Center needs three things to sync from APIM: a managed identity, RBAC access, and an integration link.

### 9a: Enable managed identity on API Center

```powershell
$subId = (az account show --query id -o tsv)
$rg = (cd infra\terraform && terraform output -raw resource_group_name)
$apiCenterName = "aigw-apicenter-xxxx"  # from terraform output

$tempFile = New-TemporaryFile
'{"identity":{"type":"SystemAssigned"}}' | Set-Content $tempFile.FullName
$apicIdentity = az rest --method PATCH `
    --uri "https://management.azure.com/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.ApiCenter/services/$apiCenterName?api-version=2024-03-01" `
    --headers "Content-Type=application/json" `
    --body "@$($tempFile.FullName)" `
    --query "identity.principalId" -o tsv
Remove-Item $tempFile.FullName
Write-Host "API Center identity: $apicIdentity"
```

> **Note:** Don't use `az apic update --identity` — it hangs for 5+ minutes. The REST API PATCH is instant.

### 9b: Grant APIM Service Reader role

```powershell
$apimName = (cd infra\terraform && terraform output -raw apim_name)
$apimId = "/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.ApiManagement/service/$apimName"

az role assignment create `
    --role "API Management Service Reader Role" `
    --assignee-object-id $apicIdentity `
    --assignee-principal-type ServicePrincipal `
    --scope $apimId -o none
```

### 9c: Create APIM → API Center integration

```powershell
az extension add --name apic-extension --allow-preview true 2>$null

az apic integration create apim `
    --resource-group $rg `
    --service-name $apiCenterName `
    --integration-name apim-sync `
    --azure-apim $apimName
```

### 9d: Verify sync

Wait 15-30 seconds, then check:

```powershell
az apic integration show `
    --resource-group $rg `
    --service-name $apiCenterName `
    --integration-name apim-sync `
    --query "{state:linkState.state}" -o table
```

**Expected:** `state: succeeded`

Then verify APIs appear:

```powershell
az rest --method GET `
    --uri "https://management.azure.com/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.ApiCenter/services/$apiCenterName/workspaces/default/apis?api-version=2024-03-01" `
    --query "value[].{name:name, title:properties.title, kind:properties.kind}" -o table
```

**Expected:**

```
Name                 Title               Kind
-------------------  ------------------  ------
<id>                 Foundry AI Gateway  rest
<id>                 microsoft-learn     mcp
```

Both the LLM gateway (REST) and the MCP server appear in API Center as a unified catalog:

![API Center Portal](images/api-center-portal.png)

## Step 10: Verify APIM metrics

1. **Portal:** APIM → Monitoring → Metrics → Requests
   - Should show requests for both the LLM API and MCP server API
   - Filter by API name to see MCP traffic separately

2. **Portal:** APIM → APIs → MCP Servers → `microsoft-learn`
   - Should show the server is registered and policy is applied

3. **Log Analytics** (if tests 6-7 passed in Step 5):

**Timechart — requests by API over time:**

```kusto
ApiManagementGatewayLogs
| where TimeGenerated > ago(30m)
| summarize count() by ApiId, bin(TimeGenerated, 1m)
| render timechart
```

**All MCP traffic (last 24 h):**

```kusto
ApiManagementGatewayLogs
| where TimeGenerated > ago(24h)
| where BackendUrl contains 'learn.microsoft.com'
| project TimeGenerated, ResponseCode, Method, CallerIpAddress, BackendResponseCode, BackendUrl, ApiId, OperationId
| order by TimeGenerated desc
```

**Response code breakdown (5-minute bins):**

```kusto
ApiManagementGatewayLogs
| where TimeGenerated > ago(24h)
| where BackendUrl contains 'learn.microsoft.com'
| summarize Count=count() by ResponseCode, bin(TimeGenerated, 5m)
| order by TimeGenerated desc
```

**200s vs 429s vs 500s (10-minute bins):**

```kusto
ApiManagementGatewayLogs
| where TimeGenerated > ago(24h)
| where ApiId contains 'learn' or BackendUrl contains 'learn.microsoft.com'
| summarize Total=count(), Passed=countif(ResponseCode == 200), RateLimited=countif(ResponseCode == 429), Errors=countif(ResponseCode >= 500) by bin(TimeGenerated, 10m)
| order by TimeGenerated desc
```

**Agent vs Tests source split:**

```kusto
ApiManagementGatewayLogs
| where TimeGenerated > ago(24h)
| where ApiId contains 'learn' or BackendUrl contains 'learn.microsoft.com'
| extend Source = iff(CallerIpAddress == '' or isempty(CallerIpAddress), 'Foundry Agent', 'Direct/Tests')
| summarize Requests=count(), AvgLatency=avg(TotalTime), Codes=make_set(ResponseCode) by Source
```

**MCP-specific log table (requires diagnostic setting):**

```kusto
// NOTE: ApiManagementGatewayMCPLog requires MCP diagnostics to be enabled in APIM.
// If no results appear, check APIM → Diagnostic settings → ensure MCP logs are routed to Log Analytics.
ApiManagementGatewayMCPLog
| where TimeGenerated > ago(24h)
| project TimeGenerated, ServerName, ToolName, Method, ClientName, SessionId, CorrelationId
| order by TimeGenerated desc
```

## Final checklist

- [ ] Terraform apply succeeded with `enable_mcp_demo=true`
- [ ] All 11 terraform outputs present (including `mcp_demo_subscription_key`)
- [ ] Foundry API imported in APIM portal (Step 3)
- [ ] Phase 1 post-deploy script completed (Step 4)
- [ ] Phase 1 smoke test returns a chat completion (Step 5)
- [ ] Phase 1 tests pass (at minimum tests 1-4; tests 5-7 may lag)
- [ ] MCP server registered in APIM (`microsoft-learn`)
- [ ] MCP governance policy applied (`mcp-governance.xml`)
- [ ] MCP governance tests pass — 4/4 (Step 7)
- [ ] MCP rate limit tests pass — 4/4, 429 at correct thresholds (Step 7)
- [ ] Foundry agent demo creates agent, invokes MCP tool through APIM, shows tool calls
- [ ] API Center synced: shows Foundry AI Gateway (REST) + microsoft-learn (MCP)
- [ ] APIM metrics show MCP traffic

## Teardown

Portal-imported APIs and stray workbooks block `terraform destroy`. Clean them first:

```powershell
cd infra/terraform
$apimName = terraform output -raw apim_name
$rg = terraform output -raw resource_group_name
$subId = (az account show --query id -o tsv)

# 1. Delete API diagnostics (they block API deletion)
az rest --method DELETE --uri "https://management.azure.com/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.ApiManagement/service/$apimName/apis/foundry-ai-gateway/diagnostics/applicationinsights?api-version=2024-05-01"
az rest --method DELETE --uri "https://management.azure.com/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.ApiManagement/service/$apimName/apis/foundry-ai-gateway/diagnostics/azuremonitor?api-version=2024-05-01"

# 2. Delete the portal-imported API
az apim api delete -g $rg -n $apimName --api-id foundry-ai-gateway --delete-revisions true -y

# 3. Delete stray workbooks (another common blocker)
az resource list -g $rg --query "[?type=='Microsoft.Insights/workbooks'].id" -o tsv | ForEach-Object { az resource delete --ids $_ }

# 4. Terraform destroy
terraform destroy -auto-approve
```

Takes ~5 min. If you plan to redeploy with the same name prefix, purge the Foundry soft-deletes:

```powershell
# Use actual account names from terraform output
az cognitiveservices account purge --name aigw-foundry-eus2-xxxx --resource-group rg-ai-gateway-demo --location eastus2
az cognitiveservices account purge --name aigw-foundry-swc-xxxx --resource-group rg-ai-gateway-demo --location swedencentral
```

## Troubleshooting

**`terraform destroy` fails with "resource still exists" on the Foundry API**

The portal-imported API (`foundry-ai-gateway`) has diagnostics resources that aren't in Terraform state. Delete the diagnostics and API manually before running destroy. See Teardown above.

**`terraform destroy` fails on workbook resource**

Azure sometimes creates diagnostic workbooks implicitly. Delete them:
```powershell
az resource list -g $rg --query "[?type=='Microsoft.Insights/workbooks'].id" -o tsv | ForEach-Object { az resource delete --ids $_ }
```

**Foundry account name conflict on redeploy**

Foundry uses soft-delete. A destroyed account still holds the name for ~48 hours. Purge it:
```powershell
az cognitiveservices account purge --name <account-name> --resource-group rg-ai-gateway-demo --location <region>
```

**MCP server registration returns 404 or "resource type not found"**

The `mcpServers` REST API is relatively new and may not be available in all regions or API versions. Fall back to the portal: APIM → APIs → MCP Servers → + Create MCP server. The `setup-mcp-demo.ps1` script prints portal instructions when this happens.

**Rate limit tests fail — never hit 429**

Check that the `mcp-governance.xml` policy was applied to the MCP server. In portal: APIM → APIs → MCP Servers → `microsoft-learn` → Policies. The policy uses `Mcp-Session-Id` header as the counter key. Verify your test requests include this header (the test scripts add it automatically via `session_id`).

**Foundry agent demo — `create_version` fails with 404**

The endpoint must include `/api/projects/<project-name>`. The terraform output may return the `.cognitiveservices.azure.com` format — the v2 agent API requires `.services.ai.azure.com/api/projects/<project>`. Set manually:
```powershell
$env:AZURE_FOUNDRY_ENDPOINT = "https://<account>.services.ai.azure.com/api/projects/<project>"
```

**Rate limit tests fail on re-run — 429 too early**

Rate limit counters are per-session and reset after 60 seconds. If you re-run tests within a minute, residual counters from the previous run may cause early 429s. Wait 60 seconds between test runs, or check that the tests use fresh UUIDs for session IDs (they do by default).

**KQL queries fail — `RequestMethod` not found or `extract()` error**

The `ApiManagementGatewayLogs` table uses `Method` (not `RequestMethod`). The `ResponseHeaders` column is `dynamic` type, so `extract()` (which expects string) fails on it. Use the `CorrelationId` column directly instead. For binary conditions, use `iff()` not `case()` (which needs odd arg count).

**`ApiManagementGatewayMCPLog` returns no results**

This dedicated MCP log table may require a diagnostic setting to be enabled. In APIM portal: Diagnostic settings → Add diagnostic setting → check MCP-related log categories → route to your Log Analytics workspace. As a workaround, use `ApiManagementGatewayLogs` filtered by `BackendUrl contains 'learn.microsoft.com'`.

**Foundry endpoint format — `.cognitiveservices.azure.com` vs `.services.ai.azure.com`**

Terraform outputs use `.cognitiveservices.azure.com`. The v2 Foundry Agent API (`create_version`, `responses.create` with `agent_reference`) requires `.services.ai.azure.com/api/projects/<project-name>`. These are different DNS names for the same underlying resource, but the API routing differs.
