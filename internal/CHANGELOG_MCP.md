# MCP Tool Governance — Changelog

Changes discovered and applied during validation runs. Use this to understand what was fixed and why, so the next run-through goes smoother.

## 2026-03-25 — Initial validation run

### Infrastructure
- `terraform.tfvars` needed real subscription_id (placeholder `your-subscription-id-here` fails)
- Windows PowerShell `-var="key=value"` quoting fails → use `.auto.tfvars` files instead
- Product-level policy with body parsing fails APIM validation on fresh deploy → use simple `rate-limit-by-key` bootstrap via Terraform, upgrade policy post-deploy via portal/script

### MCP Server Registration
- `mcpServers` ARM REST API does NOT exist on StandardV2 (tested all API versions 2024-05-01 through 2025-03-01-preview) → **portal-only** registration
- After portal registration, APIM may set backend URL to `https://learn.microsoft.com` instead of `https://learn.microsoft.com/api` → causes 403 from CDN → fix via `az rest PATCH` on the backend resource

### MCP Governance Policy
- `context.RequestId` returns `System.Guid` → needs `.ToString()` in policy expressions
- Portal policy editor requires explicit `{ return ...; }` braces in C# expressions
- Shared counter-key between `tools/call` and `tools/list` branches → prefix with `tc|` and `rd|` for independent buckets
- `context.Request.Body.As<string>()` throws 500 on empty/non-JSON bodies (MCP `initialize` request) → wrap in `try { } catch { return false; }`
- StandardV2 uses **token-bucket** algorithm (not sliding window) → exact rate limit thresholds are imprecise, tests use tolerant assertions

### Path & Header Fixes
- All file references had `learn-mcp/mcp` but actual APIM path is `learn/mcp` → bulk fixed across 9 files
- MCP subscription key header: `api-key` → `Ocp-Apim-Subscription-Key` for MCP product APIs

### Foundry Agent Demo
- Old pattern: `AgentsClient.create_agent()` + threads/runs (Assistants API) → deprecated
- New pattern: `AIProjectClient.agents.create_version()` + `PromptAgentDefinition` + `MCPTool` → `openai.responses.create()` with `agent_reference`
- `MCPTool` from `azure.ai.projects.models` supports `headers` param for subscription keys
- `McpTool` from `azure.ai.agents.models` does NOT support `headers` (different class, different SDK)
- `server_label` must match `^[a-zA-Z0-9_]+$` — no hyphens (e.g., `learn_search` not `learn-search`)
- Endpoint must be project-level: `https://<account>.services.ai.azure.com/api/projects/<project>` (NOT `.cognitiveservices.azure.com`)
- Agent creation via `create_version` auto-creates the agent — no separate "create agent" call needed
- Cleanup split to separate script: `demo/cleanup-agent.py`

### KQL Queries
- `RequestMethod` column doesn't exist → use `Method`
- `ResponseHeaders` is `dynamic` type → `extract()` fails (expects string) → use `CorrelationId` column directly
- `case()` needs odd number of args → use `iff()` for binary conditions
- `ApiManagementGatewayMCPLog` table exists but returns no data → likely needs diagnostic setting enabled
- Working queries filter by `BackendUrl contains 'learn.microsoft.com'` or `ApiId contains 'learn'`

### Tests
- `test_mcp_governance.py` — correlation ID test initially accepted `x-azure-ref` (APIM default) → fixed to require `X-Correlation-Id` specifically
- `test_mcp_governance.py` — `tools/list` response is SSE format, not JSON → added `parse_sse_json()` helper
- `test_mcp_rate_limit.py` — uses concurrent bursts via `ThreadPoolExecutor` with tolerant thresholds for token-bucket imprecision
- All 8 MCP tests pass (4 governance + 4 rate limit)

### Documentation
- Phase 1 tests (7 tests) validated working
- MCP governance tests (4 tests) validated working  
- MCP rate limit tests (4 tests) validated working
- Foundry agent demo validated working (programmatic agent creation + MCP tool invocation through APIM)

### API Center Integration
- API Center had NO integration with APIM out of the box — only the default "Swagger Petstore" sample was present
- Three prerequisites were missing:
  1. No managed identity on API Center (needed to read APIM inventory)
  2. No RBAC role (API Center identity needs "API Management Service Reader" on APIM)
  3. No integration link (the actual sync connection)
- `az apic update --identity` hangs for 5+ minutes → use REST API `PATCH` instead (instant)
- `az apic integration create apim` requires the `apic-extension` CLI extension (preview): `az extension add --name apic-extension --allow-preview true`
- After integration: both `Foundry AI Gateway` (REST) and `microsoft-learn` (MCP) sync to API Center
- MCP servers sync with `kind: mcp` — API Center portal shows type filter including MCP, Skill, A2A
- Sync state: `initializing` → `syncing` → `succeeded` (takes 15-60 seconds)

## Next run-through tips
1. Start with `mcp-demo.auto.tfvars` already containing `enable_mcp_demo = true`
2. MCP server registration is portal-only — don't waste time trying REST API
3. After registering MCP server, immediately fix the backend URL (Step 6b)
4. Apply governance policy from `scripts/policies/mcp-governance.xml` in portal
5. Use `.services.ai.azure.com` endpoint format for Foundry agent demo (not `.cognitiveservices.azure.com`)
6. Run `cleanup-agent.py --list` to check for leftover agents before running the demo
7. KQL: Use queries 1-4 from Step 10, not the `ApiManagementGatewayMCPLog` bonus query
8. API Center sync requires 3 steps: managed identity → RBAC → integration link (Step 9)
9. Use `az rest PATCH` for managed identity (not `az apic update` which hangs)
10. Install `apic-extension` before running `az apic integration create apim`
