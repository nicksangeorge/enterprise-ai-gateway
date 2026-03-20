# Quickstart

Clone to first passing test in ~25 minutes.

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Terraform | >= 1.5 | `winget install Hashicorp.Terraform` |
| Azure CLI | Latest | `winget install Microsoft.AzureCLI` |
| Python | >= 3.10 | `winget install Python.Python.3.12` |
| PowerShell 7 | >= 7.0 | `winget install Microsoft.PowerShell` |

You need **Contributor** and **User Access Administrator** roles on the target subscription.

```powershell
az login
az account set --subscription "<your-subscription-id>"
```

## Step 1: Deploy infrastructure (~15 min)

```powershell
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars - set subscription_id at minimum

terraform init
terraform plan -out=deploy.tfplan
terraform apply deploy.tfplan
```

APIM Standard v2 is the bottleneck (5-10 min). Everything else finishes in 1-3 min.

If Terraform fails on model deployments, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md#deploy-issues).

## Step 2: Deploy Kimi-K2.5 (optional, ~3 min)

Skip this if you only need GPT-5.1 and Model Router. Kimi demonstrates third-party model routing through the same gateway.

1. Go to [ai.azure.com](https://ai.azure.com) > Model catalog > search "Kimi-K2.5"
2. Deploy as Global Standard to your primary Foundry account (e.g., `aigw-foundry-eus2-xxxx`). Deployment name: `kimi-k25`
3. Repeat for the secondary account (e.g., `aigw-foundry-swc-xxxx`)

## Step 3: Import Foundry API in APIM (~2 min)

This step enables `llm-*` policy extensions. No known CLI or IaC equivalent replicates what the portal wizard does.

1. Azure portal → your APIM instance → APIs → **+ Add API**
2. Under "Create an AI API", click **Microsoft Foundry**
3. On the "Select AI Service" tab, pick your primary Foundry account (e.g., `aigw-foundry-eus2-xxxx`)
4. On the "Configure API" tab, fill in:

   | Field | Value |
   |-------|-------|
   | Display name | `Foundry AI Gateway` |
   | Name | `foundry-ai-gateway` (auto-fills) |
   | Base path | `openai` |
   | Description | (optional) |
   | Products | Leave blank. The post-deploy script handles product associations |

5. Under **Client compatibility**, select **Azure OpenAI**. Do not select "Azure AI" (creates `/models` base path) or "Azure OpenAI v1" (doubles the path to `/openai/openai/v1`).
6. Skip the remaining tabs (token consumption, semantic caching, content safety). The post-deploy script configures these.
7. Click **Review** → **Create**

The wizard auto-configures system managed identity auth to the selected Foundry account. It creates deployment-based operations under `/openai`. The post-deploy script fixes the API path if the wizard doubled it, and adds a wildcard operation so v1 paths (`/openai/v1/chat/completions`) route correctly.

## Step 4: Run post-deploy script (~3 min)

```powershell
cd scripts
.\post-deploy.ps1
```

The script reads Terraform outputs and configures:
- Fixes the API path if the wizard doubled it (`openai/openai` → `openai`)
- Adds a wildcard POST operation for v1 path routing
- Associates the API with all three team products
- Configures API-level diagnostics (Azure Monitor LLM logs + App Insights metrics)
- Applies the API-level policy (token metrics, backend pool, managed identity auth)
- Upgrades product policies from rate-limit to `llm-token-limit`
- Exports a `.env` file and prints shell env commands

The script reads Terraform outputs and configures everything APIM needs after the portal import.

## Step 5: Run tests (~2 min)

```powershell
cd scripts
. .\set_env.ps1
pip install -r ..\tests\requirements.txt
.\run_tests.ps1
```

Seven tests run in sequence: connectivity, Model Router, concurrent load, quota enforcement, failover, App Insights metrics, and LLM log ingestion. Tests 6-7 poll with backoff because Log Analytics ingestion takes 2-10 min.

## Step 6: See results

After tests pass, run these queries to confirm observability is working.

**Chargeback metrics** (App Insights > Logs):

```kusto
customMetrics
| where name == "Total Tokens"
| extend team = tostring(customDimensions["Subscription Name"])
| summarize TotalTokens = sum(value) by team
| order by TotalTokens desc
```

**LLM request logs** (Log Analytics workspace > Logs, switch to KQL mode):

```kusto
ApiManagementGatewayLlmLog
| project TimeGenerated, OperationName, BackendId,
          TotalTokens, PromptTokens, CompletionTokens,
          ModelName, Region
| order by TimeGenerated desc
```

**Gateway traffic** (Log Analytics workspace > Logs):

```kusto
ApiManagementGatewayLogs
| where BackendId contains "foundry"
| summarize count() by BackendId, bin(TimeGenerated, 1m)
| render timechart
```

> **Note:** The first two queries target different resources. `customMetrics` lives in Application Insights. `ApiManagementGatewayLlmLog` and `ApiManagementGatewayLogs` live in the Log Analytics workspace. If a query returns zero results, check that you're running it against the right resource. See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for details.

## Teardown

```powershell
cd infra/terraform
terraform destroy -auto-approve
```

Takes ~5 min. Destroys everything including portal-imported resources (they're children of APIM).

If you plan to redeploy with the same name prefix, purge the Foundry soft-delete first (names include the random suffix from your deploy):

```powershell
# Check terraform output for actual Foundry account names, then:
az cognitiveservices account purge --name aigw-foundry-eus2-xxxx --resource-group rg-ai-gateway-demo --location eastus2
az cognitiveservices account purge --name aigw-foundry-swc-xxxx --resource-group rg-ai-gateway-demo --location swedencentral
```

## Next steps

- [ARCHITECTURE.md](ARCHITECTURE.md) for component details and design decisions
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) if something breaks
