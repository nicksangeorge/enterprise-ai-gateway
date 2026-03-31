# MCP Tool Governance Demo — FAQ

Anticipated questions from demo audiences. Answers are direct and concise.

---

### 1. Why APIM for MCP governance instead of Foundry native?

APIM is agent-agnostic. Foundry agents, custom agents on AKS, Copilot Studio agents, and third-party agents (LangChain, CrewAI) all consume tools through the same gateway. Foundry's built-in tool catalog only governs Foundry agents. If you're a single-platform Foundry shop, native tools work fine — but most enterprises have multiple agent platforms, and APIM covers all of them with one policy layer.

See: [Architecture decision](tools-governance-plan.md#architecture-decision-apim-as-upstream-source-of-truth)

### 2. Can developers bypass this and add their own MCP servers?

In dev, yes. In production, you layer defenses: Foundry's private tool catalog with RBAC restricts which tools developers can see. Network controls (NSGs/firewalls) block outbound to anything except APIM. CI/CD pipelines scan for unauthorized MCP URLs and block the PR. Agent 365 detects shadow tool usage after deployment. No single killswitch — it's prevention where possible, detection everywhere else.

See: [How enforcement actually works](tools-governance-plan.md#how-enforcement-actually-works)

### 3. What's the difference between mcp-governance.xml and the product policies (product-alpha.xml)?

Product policies (`product-alpha.xml`, `product-beta.xml`, etc.) control per-team rate limits for LLM inference — token-based quotas scoped by APIM subscription. `mcp-governance.xml` controls MCP tool calls specifically: it parses the JSON-RPC body, differentiates `tools/call` (write, 10/min) from `tools/list` (read, 60/min), and rate-limits per MCP session ID. Different policy, different protocol, different rate-limit key.

See: [`mcp-governance.xml`](../infra/terraform/modules/apim-config/policies/mcp-governance.xml), [`product-alpha.xml`](../infra/terraform/modules/apim-config/policies/product-alpha.xml)

### 4. How does API Center relate to APIM?

APIM is the execution layer — it enforces policies on every tool call. API Center is the discovery layer — it's the catalog where developers find available tools, read descriptions, and get connection info. APIM syncs registered MCP servers to API Center automatically. Developers browse API Center without needing APIM management-plane access. Foundry's tool catalog (`Build > Tools`) also pulls from API Center via the private tool catalog integration (preview).

See: [Component architecture](tools-governance-plan.md#component-architecture)

### 5. What's Agent 365 and when is it available?

Agent 365 is Microsoft's non-functional governance layer for agents. It provides an agent registry, OpenTelemetry-based observability SDK, tool usage tracing, shadow AI detection, blast-radius analysis, and automated circuit breakers. GA is May 1, 2026, included in M365 E7 ($15/user/month — licensed per user, not per agent). Python, .NET, and JavaScript SDKs are in preview now.

See: [Agent 365 section](tools-governance-plan.md#agent-365-the-non-functional-governance-layer)

### 6. Can this work with non-Microsoft agents (LangChain, CrewAI, etc.)?

Yes. Any agent that can make HTTP requests to an MCP server can point at the APIM gateway URL instead of the direct endpoint. APIM doesn't care what's calling it — it enforces the same policies regardless. The agent just needs the gateway URL and a subscription key (or OAuth token). No SDK dependency on Microsoft.

### 7. What about MCP servers that need OAuth authentication?

APIM supports OAuth 2.1, Entra ID token validation (`validate-azure-ad-token`), API keys, and managed identity. For MCP servers requiring OAuth, APIM can validate the incoming token and forward credentials to the backend. The `mcp-governance-auth.xml` policy variant shows Entra ID validation with tenant and allowed client app IDs. One limitation (March 2026): Foundry AI Gateway auto-routing only works for MCP tools that don't use managed OAuth — tools with managed OAuth need direct configuration.

See: [`mcp-governance-auth.xml`](../infra/terraform/modules/apim-config/policies/mcp-governance-auth.xml)

### 8. How do we see which agents are using which tools?

Two paths. APIM gives you request-level metrics: which subscription (team) called which MCP server, when, how many times, success/failure rates. Check APIM Monitoring > Metrics and Monitoring > Logs with the `X-Correlation-Id` header. Agent 365 (GA May 2026) adds agent-level tracing: which specific agent called which tool with what parameters, plus relationship graphs and blast-radius analysis. APIM tells you about tool traffic. Agent 365 tells you about agent behavior.

### 9. What happens when a rate limit is hit — does the agent get an error?

The agent receives a standard HTTP 429 Too Many Requests response from APIM. The response includes a `Retry-After` header indicating when the agent can try again. Well-built agents handle 429s with backoff and retry. The MCP server itself never sees the excess requests — APIM rejects them before they reach the backend.

### 10. Can we test this locally without Azure?

Partially. You can run a local MCP server (see `demo/mcp-test-backend.py` if available) and test MCP protocol interactions. But the governance layer — rate limiting, correlation IDs, metrics, API Center discovery — requires APIM. There's no local emulator for APIM policies. For a full test, deploy to Azure using `terraform apply` (~25 minutes). See [QUICKSTART.md](QUICKSTART.md).
