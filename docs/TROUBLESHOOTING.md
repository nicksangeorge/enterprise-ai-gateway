# Troubleshooting

## Deploy issues

**APIM name collision (409 on create)**

APIM names are globally unique DNS names. If `terraform apply` fails with a naming conflict, either set `apim_name` explicitly in `terraform.tfvars` or enable `use_random_suffix = true`.

**Foundry model deployment 409**

Model Router and GPT-5.1 deploying in parallel on the same account can hit a conflict. Terraform already uses `depends_on` between deployments. If it still fails, run `terraform apply` again. The second run succeeds because the first deployment completes.

**Foundry soft-delete conflict**

After `terraform destroy`, Foundry account names are soft-deleted for 48 hours. Immediate redeployment with the same prefix fails. Fix:

```powershell
az cognitiveservices account purge --name aigw-foundry-eus2 --resource-group rg-ai-gateway-demo --location eastus2
az cognitiveservices account purge --name aigw-foundry-swc --resource-group rg-ai-gateway-demo --location swedencentral
```

Or use a different prefix / enable `use_random_suffix`.

**API Center region not available**

API Center isn't available in all regions. If deployment fails, set `api_center_location` in `terraform.tfvars` to a supported region (default: `eastus`).

## Auth issues

**401 from Foundry backend**

APIM's managed identity doesn't have `Cognitive Services OpenAI User` on the Foundry account. This commonly happens on the Sweden Central account because the portal import wizard only grants RBAC on the account you select (East US 2). The post-deploy script handles this, but if you skipped it:

```powershell
az role assignment create `
  --role "Cognitive Services OpenAI User" `
  --assignee <apim-system-identity-principal-id> `
  --scope <foundry-swc-resource-id>
```

RBAC propagation takes 1-5 minutes after assignment. If tests fail with 401 immediately after running the post-deploy script, wait and retry.

**403 from APIM**

The subscription key is missing or invalid. Check:
- The `api-key` header is set in the request
- The key belongs to a product that's associated with the API
- The product subscription is active (not suspended)

**500 from APIM**

Usually means managed identity isn't configured on the backend or the backend URL is wrong. Check:
- Backend resource in APIM has `credentials.managedIdentity.resource = "https://cognitiveservices.azure.com/"`
- Backend URL points to a valid Foundry endpoint
- The Foundry account exists and has at least one active deployment

## Observability issues

**Three layers, three failure modes.** Full observability requires all three to be configured. Missing any one silently breaks part of the telemetry.

| Layer | What it does | Created by | If missing |
|-------|-------------|------------|------------|
| Azure Monitor diagnostic setting | Pipes `GatewayLogs` + `GatewayLlmLogs` to Log Analytics (dedicated tables) | Terraform | No gateway or LLM logs in Log Analytics at all |
| API-level `azuremonitor` diagnostic | Turns on LLM log generation for the specific API | Post-deploy script | Gateway logs appear, but `ApiManagementGatewayLlmLog` is empty |
| API-level `applicationinsights` diagnostic | Routes `llm-emit-token-metric` output to App Insights | Post-deploy script | No `customMetrics` entries in App Insights |

**`ApiManagementGatewayLlmLog` returns zero rows**

1. Confirm the diagnostic setting exists: APIM > Diagnostic settings. Should show one setting with both `GatewayLogs` and `GatewayLlmLogs` categories enabled, destination type Dedicated.
2. Confirm the API-level diagnostic: the post-deploy script creates an `azuremonitor` diagnostic on the imported API with `largeLanguageModel.logs = "enabled"`. If this is missing, the diagnostic setting has nothing to pipe.
3. Wait. Log Analytics ingestion takes 2-10 minutes.

**Table name is singular.** The diagnostic category is `GatewayLlmLogs` (plural), but the dedicated table is `ApiManagementGatewayLlmLog` (singular). This is a known Azure naming inconsistency.

**`customMetrics` returns zero rows**

Query `customMetrics` from the **App Insights** resource, not the Log Analytics workspace. These are different query scopes. The `llm-emit-token-metric` policy emits to App Insights via the Application Insights logger, not to Log Analytics.

**KQL editor not visible in APIM Logs blade**

The APIM portal Logs blade defaults to "Simple mode," which doesn't accept raw KQL. Either:
- Click the toggle to switch from "Simple mode" to "KQL mode"
- Go directly to the Log Analytics workspace resource and query from there

**Diagnostic setting uses AzureDiagnostics mode (v1 leftover)**

If your diagnostic setting was created before v2, it may use `AzureDiagnostics` destination type. In that mode, logs land in the generic `AzureDiagnostics` table with `_s` suffixed columns. Queries against `ApiManagementGatewayLogs` return nothing. Fix: delete the old diagnostic setting and let Terraform recreate it with `Dedicated` mode.

Workaround query for AzureDiagnostics mode:

```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.APIMANAGEMENT"
| where Category == "GatewayLogs"
```

## Policy issues

**`llm-*` policy validation fails**

The `llm-emit-token-metric` and `llm-token-limit` policies require the AI Gateway policy extensions, which are only enabled after importing a Foundry API through the portal wizard (Step 3 in [QUICKSTART.md](QUICKSTART.md)). If you try to apply these policies before the import, APIM rejects them with a validation error.

Fix: complete the portal import first, then rerun the post-deploy script.

**`estimate-prompt-tokens` error at product level**

The `llm-token-limit` policy at product scope does not support `estimate-prompt-tokens="true"`. Set it to `false`. Similarly, `remaining-tokens-header-name` and `tokens-consumed-header-name` attributes are blocked at product level. Only use these at API or operation level.

**`api-version` 400 error from Foundry**

The v1 path (`/openai/v1/...`) rejects `api-version` as a query parameter with HTTP 400. If you're seeing this, the `set-query-parameter` policy to strip `api-version` isn't applied, or the client is sending it explicitly. The post-deploy script includes this in the API policy. The standard `OpenAI()` SDK doesn't send `api-version` by default, but `AzureOpenAI()` does.

## Failover issues

**Circuit breaker not triggering**

The circuit breaker trips after 3 consecutive errors within 60 seconds on a backend. With GlobalStandard capacity 30, natural quota exhaustion is hard to trigger with low traffic. Options:
- Temporarily lower the primary deployment's TPM for demo purposes
- Use the `test5_failover.py` script which sends rapid bursts
- Verify the circuit breaker rule exists on the backend: APIM > Backends > select backend > check circuit breaker configuration

**401 on secondary region after failover**

APIM's system identity needs RBAC on both Foundry accounts. The portal import wizard only grants it on the account you selected during import (East US 2). The post-deploy script grants it on Sweden Central. If you see 401s only when traffic fails over, the secondary RBAC assignment is missing. See the [Auth issues](#auth-issues) section above.

## MCP issues

**MCP server returns 403**

The backend URL is missing the `/api` suffix. When registering an external MCP server through APIM, the **MCP server base URL** must include `/api` if that's part of the endpoint path. For example:
- ❌ Wrong: `https://mcp-provider.example.com/mcp`
- ✅ Correct: `https://mcp-provider.example.com/api/mcp`

Check the MCP server's documentation for the correct endpoint and verify the full path is registered in APIM.

**Policy validation fails on C# expressions**

Custom C# policies in APIM require braces around the expression body. When writing policy validation logic for MCP tools:
- ❌ Wrong: `@(context.Request.Body.Contains("tools/call"))`
- ✅ Correct: `@{ return context.Request.Body.Contains("tools/call"); }`

The `{ return ...; }` braces are mandatory even for single-line expressions. Use tools like the policy XML validator in APIM portal to catch these before deployment.

**Rate limit tests fail for tool calls**

StandardV2 tier uses token-bucket rate limiting, not sliding window. When testing MCP tool rate limits:
- Token bucket means requests can burst up to the limit, then refill at a steady rate
- Sliding window (older models) rejects as soon as the window fills
- If your test expects gradual rejection but gets none, the bucket hasn't emptied yet
- Run the test again after a full renewal period (`renewal-period` value in your policy)

For reliable testing, either wait between test runs or use a backend that supports sliding-window rate limiting.

**MCP registration requires portal (no ARM API)**

As of March 2026, MCP server registration in APIM is portal-only. There is no ARM API or Terraform support for creating MCP servers. To register an MCP server:
1. Open the Azure portal
2. Navigate to **APIM instance** > **APIs** > **MCP Servers** > **+ Create MCP server**
3. Fill in the server URL, transport type, and governance policies
4. Save

Governance policies (rate limiting, logging, correlation IDs) can be managed via ARM or Terraform after the server is created, but the initial registration must be done in the portal.
