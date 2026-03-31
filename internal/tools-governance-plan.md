# MCP Tool Governance & Unified Tool Catalog — Plan

*Last updated: 2026-03-24 | Status: Cross-referenced against live sources, draft implementation plan ready*

> **Cross-reference status (2026-03-24):** All claims verified against live Microsoft Learn docs, Feb/Mar 2026 web sources, internal SharePoint decks (6 found), CDW A365 meeting transcript, and Teams chats. Corrections applied inline. See [Cross-Reference Log](#cross-reference-log) at bottom.

## Problem statement

Enterprise agents consume tools (MCP servers, REST APIs, Foundry-managed tools) from multiple sources with no central registry, no consistent auth enforcement, and no unified observability. Teams independently wire up MCP servers, creating tool sprawl, duplicated integrations, and ungoverned access to sensitive systems.

This demo section proves that APIM + API Center can serve as the **single governed tool catalog** upstream of all agent platforms — Foundry agents, custom agents on AKS, Copilot Studio agents, and third-party agents alike.

---

## Architecture decision: APIM as upstream source of truth

Two approaches exist. We chose APIM-first.

| Approach | Source of truth | Pros | Cons |
|----------|----------------|------|------|
| **APIM + API Center (chosen)** | APIM owns tool registration, API Center is the discovery surface | Agent-agnostic; same governance for Foundry, custom, and third-party agents; existing policy/auth infrastructure; mature RBAC and rate limiting | Foundry integration still preview; requires AI Gateway connection |
| Foundry-native | Foundry's built-in tool catalog | Tighter integration with Foundry Agent Service; simpler for single-platform shops | Foundry-only governance; no coverage for non-Foundry agents; MCP governance still preview with limitations |

**Why APIM wins for enterprise:** Per the internal Teams discussions (Jack Johnson, Creighton, Jacob, Nick San George — March 2026), the clear consensus is that APIM is already the investment customers have for API governance. Foundry is positioned as **one consumer** of the governed catalog, not the owner. Custom agents, AKS-hosted agents, and partner agents all consume the same governed tools through the same APIM gateway.

> "APIM / API Center is the system of record for MCP servers. MCP servers registered in API Center appear automatically in Foundry's tool catalog. All platforms hit the same tools through APIM." — Teams chat synthesis

---

## Component architecture

```
┌──────────────────────────────────────────────────────────────┐
│                     API Center                                │
│              (Private MCP Registry / Discovery)               │
│  ┌─────────────┐  ┌─────────────┐  ┌───────────────────┐    │
│  │ APIM MCP    │  │ Foundry     │  │ Partner / Custom  │    │
│  │ Servers     │  │ Tools       │  │ MCP Servers       │    │
│  └──────┬──────┘  └──────┬──────┘  └─────────┬─────────┘    │
│         │ auto-sync      │ sync              │ register      │
└─────────┼────────────────┼───────────────────┼───────────────┘
          │                │                   │
          ▼                ▼                   ▼
┌──────────────────────────────────────────────────────────────┐
│                  APIM AI Gateway                              │
│         (Governed Execution & Policy Layer)                    │
│                                                               │
│  ┌────────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐  │
│  │ Auth       │ │ Rate     │ │ Logging  │ │ Correlation  │  │
│  │ (Entra/    │ │ Limiting │ │ & Audit  │ │ ID Tracing   │  │
│  │ OAuth/Key) │ │ per-tool │ │          │ │              │  │
│  └────────────┘ └──────────┘ └──────────┘ └──────────────┘  │
└──────────────────────────┬───────────────────────────────────┘
                           │
          ┌────────────────┼────────────────┐
          ▼                ▼                ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ Foundry      │  │ Custom       │  │ Copilot      │
│ Agents       │  │ Agents (AKS) │  │ Studio       │
└──────────────┘  └──────────────┘  └──────────────┘

          ┌────────────────────────────────────┐
          │        Agent 365                    │
          │  (Observability & NFR Governance)   │
          │  Identity · Telemetry · Compliance  │
          └────────────────────────────────────┘
```

### Component responsibilities

| Component | Role | Key capabilities |
|-----------|------|------------------|
| **Azure API Management** | Governed execution layer | MCP server hosting (proxy existing or expose REST-as-MCP); policy enforcement (auth, rate limits, IP filtering, caching); AI Gateway for Foundry tools routing |
| **Azure API Center** | Discovery catalog / private MCP registry | Register remote/local/partner MCP servers; metadata, versioning, lifecycle management; one-way sync from APIM (requires initial config, propagates within minutes–24h); API Center portal for developer self-service; **Foundry private tool catalog integration (preview)** — RBAC-gated discovery under `Build > Tools` |
| **Microsoft Foundry** | Agent runtime + consumer | Agents consume governed tools via AI Gateway; native tools (AI Search, SharePoint, code interpreter) auto-route through APIM when AI Gateway is connected; tool catalog UI (`Build → Tools`) surfaces API Center entries |
| **Agent 365** | Non-functional governance | Agent registry (all agent types); OpenTelemetry-based observability SDK (Python/.NET/JS); tool usage tracing; Entra Agent ID; blast-radius analysis + relationship graphs; lifecycle governance (sponsorship, orphan detection, automated retirement); shadow AI detection via Entra Internet Access; automated circuit breakers; compliance/audit/cost tracking |

---

## Governance capabilities matrix

| Capability | APIM (functional) | Agent 365 (non-functional) | Status |
|------------|--------------------|-----------------------------|--------|
| **Tool registration** | Register MCP servers in APIM, one-way sync to API Center (requires config) | Agents auto-register when instrumented with A365 SDK | GA (APIM) / GA May 2026 (A365) |
| **Authentication** | Entra ID (validate-azure-ad-token), OAuth 2.1, API keys, managed identity, credential manager | Entra Agent ID for each agent instance | GA |
| **Rate limiting** | `rate-limit-by-key` per session/user/subscription; `llm-token-limit` for model calls | N/A (delegated to APIM) | GA |
| **Tool-level access control** | APIM products + subscriptions scope which teams can call which tools | Role-based via Entra; least-privilege policies | GA |
| **Audit logging** | Azure Monitor + App Insights; X-Correlation-Id tracing; GatewayLogs | A365 captures every tool invocation, parameters, responses | GA / Preview |
| **Tool discovery** | API Center portal; VS Code extension; Foundry tool catalog | Agent registry shows which agents use which tools | GA / Preview |
| **Shadow tool detection** | N/A | A365 detects unapproved/unregistered tool usage | Preview (via Entra Internet Access) |
| **Cost tracking** | `llm-emit-token-metric` for model costs; request metrics per tool | A365 dashboard: LLM inference + tool cost attribution | GA / Preview |
| **Blast radius analysis** | N/A | Agent ↔ tool relationship graphs, dependency mapping, impact chain visualization | GA May 2026 |
| **Content safety** | APIM policies (header stripping, payload inspection) | Purview content safety policies on agents | Preview |

---

## Three registration paths

### Path 1: Proxy an existing remote MCP server through APIM

Already demonstrated in our demo (`docs/MCP_ONBOARDING.md` Pattern 1). External MCP server (e.g., Microsoft Learn) gets proxied through APIM. Governance policies applied via XML.

**Flow:** MCP server exists → Register in APIM (`APIs > MCP Servers > Expose existing`) → Apply policies → Sync to API Center → Agents discover via catalog

### Path 2: Expose an existing REST API as an MCP server

Already demonstrated in our demo (`docs/MCP_ONBOARDING.md` Pattern 2). Any REST API managed in APIM becomes MCP-compatible. APIM generates tool definitions from OpenAPI spec.

**Flow:** REST API in APIM → `APIs > MCP Servers > Expose API as MCP` → Select operations → Each operation becomes an MCP tool → Apply policies → Sync to API Center

### Path 3: Foundry-managed tools auto-routing through AI Gateway

When AI Gateway is connected to Foundry, new MCP tools created in Foundry portal automatically route through APIM. Tool endpoint becomes the APIM gateway URL instead of direct.

**Flow:** Connect AI Gateway to Foundry → Add MCP tool in Foundry (`Build > Tools > Custom > MCP`) → Endpoint auto-rewrites to APIM gateway URL → Policies applied in Azure portal

**Limitation (March 2026):** Only new MCP tools that don't use managed OAuth are routed. Existing tools need re-creation. Foundry-native tools (SharePoint, code interpreter) and OpenAPI tools are not yet supported through the gateway.

---

## Agent 365: the non-functional governance layer

From the CDW A365 overview meeting (March 13, 2026 — Jack Johnson, Michael Davidson, Datthesh Shenoy, Anurag Batra, Nick San George, Goutham Bandapati):

### What Agent 365 adds on top of APIM

APIM governs the **functional plane** (auth, rate limits, routing). Agent 365 governs the **non-functional plane** (identity, observability, compliance, cost).

| A365 Capability | What it means for tool governance |
|-----------------|-----------------------------------|
| **Agent registry** | Single pane showing ALL agents (Foundry, Copilot Studio, custom, third-party) and which tools each agent accesses |
| **OpenTelemetry-based observability SDK** | Wraps agent logic, tool calls, and LLM inference. Available in Python, .NET, JavaScript. Every invocation is traced with distributed context propagation. |
| **Tool usage tracing** | Captures tool invocations, parameters passed, responses, failures — even for unapproved tools |
| **Entra Agent ID** | Each agent gets an enterprise identity. Treated like a user: lifecycle management, access control, licensing |
| **Blast-radius analysis** | Relationship graphs showing agent→tool dependencies; impact chain visualization; OWASP-aligned risk assessment |
| **Shadow AI detection** | Via Entra Internet Access: detect agents calling tools outside the governed catalog; network-level prompt injection blocking |
| **Lifecycle governance** | Sponsorship workflows, orphan agent detection, automated retirement of unused agents |
| **Automated circuit breakers** | Pause agents across services on anomaly detection |

### NFRs identified from the CDW discussion

- **Traceability:** Every agent action must be traceable end-to-end
- **Blast-radius awareness:** Tool changes must have impact analysis
- **Security posture:** Detect unapproved tool usage automatically
- **Cost/performance:** LLM inference and tool usage must be measurable per-agent
- **Exportability:** Agent metadata and relationships must be extractable for EA systems

### Open gaps (as of March 2026)

- Agent ↔ tool relationship graphs ship at GA (May 1) — dashboards show agent→tool dependencies, impact chains
- External EA system integration (e.g., Spectra) requires export pipelines and possibly custom connectors
- Observability is not transitive: if a downstream agent/tool is not wrapped with A365 SDK, only the call + response are visible — internal behavior is opaque (architecturally inherent to OpenTelemetry context propagation)
- GA date: May 1, 2026 (included in M365 E7 at $15/user/month, **licensed per user not per agent instance** — OBO agents covered under user license; per-agent-instance licensing for autonomous agents is Frontier-only, pricing TBD)
- A365 SDK currently in preview: Python, .NET, JavaScript (NuGet: `Microsoft.Agents.A365.Observability.Runtime 0.2.127-beta`)

---

## Demo section plan: "MCP tool governance, unified tool catalog"

### Demo flow (10-15 minutes)

#### Part 1: The problem (2 min)
Show the "before" state: multiple agents each hardcoding tool endpoints, no central visibility, no consistent auth, no audit trail. Pull up a slide showing 5 teams, 12 agents, 30+ tools — ungoverned.

#### Part 2: Register tools in APIM (3 min)
Live in the portal:
1. **Proxy an external MCP server** — Register Microsoft Learn MCP server through APIM (`APIs > MCP Servers > Expose existing MCP server`). ~90 seconds.
2. **Expose a REST API as MCP** — Take the Echo API already in APIM, expose it as an MCP server. Each operation becomes a tool. ~60 seconds.

#### Part 3: Apply governance policies (2 min)
On the Microsoft Learn MCP server:
- Apply rate limiting (30 calls/min per MCP session)
- Add correlation ID header
- Show the `mcp-governance.xml` policy from our repo

Talk track: "Two minutes to register. One policy file for governance. Same XML policy language your APIM teams already know."

#### Part 4: Discover tools in API Center (2 min)
- Show API Center portal with the registered MCP servers
- Demonstrate auto-sync from APIM to API Center
- Show developer view: browse tools, see descriptions, get connection info, install to VS Code
- Show Foundry tool catalog (`Build > Tools`) pulling from API Center

Talk track: "One catalog. Three registration paths. Every agent — Foundry, custom, third-party — discovers the same set of governed tools."

#### Part 5: Foundry agent consumes governed tool (3 min)

Build and run a real Foundry agent that pulls its tools from APIM — not hardcoded, not direct. The agent doesn't know it's governed. It just calls a URL. APIM handles the rest.

**Live code walkthrough:**

```python
from azure.ai.projects import AgentsClient, McpTool

# Tool URL points at APIM gateway, NOT the raw MCP server
mcp_tool = McpTool(
    server_label="learn-search",
    server_url="https://<your-apim>.azure-api.net/learn/mcp",
    auth_header={"Ocp-Apim-Subscription-Key": api_key}
)

agents_client = AgentsClient.from_connection_string(conn_string)
agent = agents_client.create_agent(
    model="gpt-51",
    name="demo-governed-agent",
    instructions="Use the Learn search tool to answer questions about Azure.",
    tools=mcp_tool.definitions
)
```

**Demo steps:**
1. Show the agent code — `server_url` points at APIM, not `learn.microsoft.com` directly
2. Run the agent: "Search Microsoft Learn for APIM rate limiting best practices"
3. Agent invokes the tool → response comes back → show it worked
4. Switch to APIM metrics dashboard: the request appears with 200, correlation ID, session info
5. Rapid-fire calls → show 429 from rate limiting kicking in
6. Punchline: "The agent didn't know it was governed. It called a URL. APIM handled auth, rate limits, and logging transparently."

**Reference implementations:**
- [`Azure-Samples/foundry-agent-service-remote-mcp-python`](https://github.com/Azure-Samples/foundry-agent-service-remote-mcp-python) — quickstart with Azure Functions + APIM + Python
- [`pablocast/gbb-ai-mcp-with-apim-aifoundry`](https://github.com/pablocast/gbb-ai-mcp-with-apim-aifoundry) — end-to-end Bicep + Python with APIM orchestration

**Optional extension:** Also show VS Code + Copilot agent mode consuming the same APIM-proxied tool, proving that the same governed endpoint works for both Foundry agents and coding agents.

#### Part 6: Agent 365 observability (2-3 min)
Show (slide or live if preview access available):
- Agent registry showing all registered agents
- Tool usage dashboard: which agents called which tools, when, with what parameters
- Blast-radius view: "If this MCP server goes down, which agents are affected?"
- Shadow AI detection: an agent calling an unregistered tool gets flagged

Talk track: "APIM handles the functional governance. Agent 365 handles the non-functional side — identity, observability, compliance. Together, they give you complete coverage."

### Talk track summary
> "Here's how we think about tool governance for enterprise agents. APIM is the functional control plane — auth, rate limits, routing, logging. API Center is the discovery surface — one catalog, three registration paths, every team finds the same tools. Agent 365 is the non-functional layer — it tells you which agents are using which tools, what the blast radius is when something changes, and whether anyone is using unapproved tools outside your catalog. APIM is upstream because it's agent-agnostic. Foundry consumes it. Custom agents consume it. Partner agents consume it. One governance layer for everything."

---

## How enforcement actually works

A common question: "Can't any developer just add a random MCP server and bypass all this?" The honest answer is **yes, in dev — but not in production, if you build the right layers.** Enforcement is not a single switch. It's a layered model: prevention where possible, detection everywhere else.

### The enforcement stack

```
┌───────────────────────────────────────────────────┐
│  LAYER 1: PREVENTION (hard enforcement)           │
│                                                   │
│  Foundry:   Private tool catalog + RBAC lockdown  │
│  Network:   NSG/firewall → outbound only to APIM  │
│  APIM:      Auth, rate limits, IP filtering       │
│  Pipeline:  Allowlist scan in CI/CD               │
│  GHCP:      Enterprise admin MCP server policy    │
└─────────────────────┬─────────────────────────────┘
                      │ some things get through
                      ▼
┌───────────────────────────────────────────────────┐
│  LAYER 2: DETECTION (soft enforcement)            │
│                                                   │
│  Agent 365:  Shadow AI detection                  │
│  Agent 365:  Tool usage tracing (all invocations) │
│  Agent 365:  Anomaly → automated circuit breaker  │
│  APIM logs:  Unrecognized endpoint alerts         │
└───────────────────────────────────────────────────┘
```

### By agent type

#### Foundry agents — lockable

Foundry's **private tool catalog** (preview) gives you real enforcement:

1. Register approved tools in API Center → they appear in Foundry's `Build > Tools`
2. Assign RBAC (Data Reader) only to approved users/projects — others can't see the tools
3. Connect AI Gateway → all new MCP tools auto-route through APIM
4. Restrict who has the **Tool Contributor** role — only platform team can add tools
5. **Network layer:** use NSGs/firewall to block outbound from Foundry to anything except APIM. Even if someone adds a rogue MCP URL, the network won't let it through.

**The gap:** A project Owner can still add a custom MCP server via the portal. Network controls are the backstop — block outbound to non-APIM endpoints in production subscriptions.

#### Code-based agents (custom agents on AKS, VMs) — pipeline enforcement

Code-based agents can do whatever they want in code. You can't platform-prevent a `requests.post("https://random-mcp.com")`. This is a **CI/CD governance problem**.

1. **Policy-as-code in the pipeline** — scan for MCP server URLs in code/config. Only allow URLs matching `https://<your-apim>.azure-api.net/*`. Flag anything else as a PR blocker.
2. **Allowlist in config** — maintain a JSON allowlist of approved MCP endpoints. CI pipeline validates agent configs against it before deployment.
3. **A365 SDK requirement** — production agents must be wrapped with the Agent 365 SDK. If an agent isn't instrumented, it doesn't get deployed. The SDK traces all tool calls.
4. **Network policy** — production AKS namespaces / VM NSGs only allow outbound to APIM IPs. Direct calls to arbitrary MCP endpoints get blocked.
5. **Post-deployment detection** — Agent 365 shadow AI detection catches agents calling tools outside the governed catalog, even if they slipped past the pipeline.

#### GitHub Copilot / coding agents — enterprise admin controls

Enterprise GitHub Copilot lets admins control which MCP servers are allowed via **organization-level policy**. This is the most locked-down path — developers can't add MCP servers that aren't on the approved list.

#### Agent 365 — the catch-all safety net

Agent 365 doesn't prevent bad behavior — it **detects** it. Think of it as the audit layer:

- Every tool invocation is traced (approved or not)
- Shadow AI detection flags unregistered tools via Entra Internet Access
- Automated circuit breakers can pause agents on anomaly detection
- Blast-radius analysis shows impact if a tool is compromised

### How APIM tool catalog and Agent 365 tool registry relate

They are **complementary, not competing.** Different sides of the same governance coin.

| | APIM + API Center | Agent 365 |
|---|---|---|
| **What it tracks** | Tools / MCP servers (the supply side) | Agents (the demand side) |
| **Primary function** | "What tools exist, who can use them, enforce policy on every call" | "What agents exist, what are they doing, are they compliant" |
| **Enforcement type** | Hard — auth, rate limits, network blocking | Soft — detection, alerting, audit + hard via circuit breakers |
| **Registration** | Platform team registers tools in APIM/API Center | Agents auto-register when instrumented with A365 SDK |
| **Scope** | Tool-centric: controls what's available | Agent-centric: controls what's consuming |

**Together:** APIM governs what tools are available and enforces policy on every call. Agent 365 watches what agents are actually doing and catches anything that slips through. One without the other leaves a gap.

### Recommended governance model for production

| Environment | Prevention | Detection | Approach |
|-------------|-----------|-----------|----------|
| **Sandbox / Dev** | Minimal — let developers experiment | A365 SDK recommended but not required | Bottom-up with guardrails |
| **Staging** | Pipeline scans, network controls | A365 SDK required, full tracing | Validate before production |
| **Production** | Full lockdown: private catalog, RBAC, NSG, pipeline allowlist | A365 SDK mandatory, circuit breakers armed, shadow AI detection active | Top-down enforcement |

This matches the **crawl → walk → run** adoption pattern discussed in the CDW A365 session.

---

## Policy reference

### MCP session-based rate limiting

```xml
<policies>
    <inbound>
        <base />
        <set-variable name="body" value="@(context.Request.Body.As<string>(preserveContent: true))" />
        <choose>
            <when condition="@(
                Newtonsoft.Json.Linq.JObject.Parse((string)context.Variables[&quot;body&quot;])[&quot;method&quot;] != null
                && Newtonsoft.Json.Linq.JObject.Parse((string)context.Variables[&quot;body&quot;])[&quot;method&quot;].ToString() == &quot;tools/call&quot;
            )">
                <rate-limit-by-key
                    calls="30"
                    renewal-period="60"
                    counter-key="@(context.Request.Headers.GetValueOrDefault(&quot;Mcp-Session-Id&quot;, &quot;unknown&quot;))" />
            </when>
        </choose>
        <set-header name="X-Correlation-Id" exists-action="override">
            <value>@(context.RequestId)</value>
        </set-header>
    </inbound>
    <backend><base /></backend>
    <outbound><base /></outbound>
    <on-error><base /></on-error>
</policies>
```

### Entra ID token validation for MCP

```xml
<inbound>
    <base />
    <validate-azure-ad-token tenant-id="{{tenant-id}}" header-name="Authorization" failed-validation-httpcode="401">
        <client-application-ids>
            <application-id>{{allowed-client-app-id}}</application-id>
        </client-application-ids>
    </validate-azure-ad-token>
</inbound>
```

### IP filtering for trusted networks

```xml
<inbound>
    <base />
    <ip-filter action="allow">
        <address>10.0.0.0/24</address>
        <address>20.50.123.45</address>
    </ip-filter>
</inbound>
```

---

## Two governance models (from CDW A365 discussion)

> **Key framing from internal discussions:** Whether APIM or Foundry "owns" the tool catalog is an **EA decision, not a product decision**. Our recommendation is APIM-first because it's agent-agnostic, but customers should make this call based on their architecture.

### Top-down (EA-led)
- Central tool registry defines approved tools
- Agents consume only from the registry
- Prevents tool sprawl (e.g., multiple web search MCPs)
- Enables architectural standards and review boards
- **AI council / gated approval** — new tools require review before production registration (explicitly discussed in CDW session)
- **Implementation:** APIM products + API Center = approved tool catalog. Agents only get subscription keys for their assigned products.

### Bottom-up (developer-led with guardrails)
- Custom agents can introduce tools via code
- Agent 365 still detects and traces all tool usage
- Unapproved tools flagged, audited, remediated post-deployment
- **Implementation:** A365 SDK wraps all agents. Shadow tool detection via Entra Internet Access. Alert on unregistered tool calls.

**Recommended approach:** Start top-down for production agents, allow bottom-up for innovation/sandbox environments. Governance model matches the crawl → walk → run adoption pattern. **Production agents must be wrapped with A365 SDK** — this was an explicit requirement from the CDW discussion.

---

## Implementation roadmap for this demo

### Phase 1: Register tools (already partially done)
- [x] API Center deployed (`infra/terraform/modules/api-center/main.tf`)
- [x] MCP governance policy written (`infra/terraform/modules/apim-config/policies/mcp-governance.xml`)
- [x] MCP onboarding doc written (`docs/MCP_ONBOARDING.md`)
- [ ] Configure APIM-to-API-Center sync link (one-way, requires initial config in portal or via `az rest`)
- [ ] Register Microsoft Learn MCP server in APIM (live, not just documented)
- [ ] Register Echo API as MCP server (demo tool)

### Phase 2: Foundry AI Gateway connection
- [ ] Connect APIM as AI Gateway to Foundry resource
- [ ] Create an MCP tool in Foundry that auto-routes through APIM
- [ ] Verify policy enforcement on Foundry-originated tool calls
- [ ] Document the Foundry → APIM → MCP server flow
- [ ] Note: only new MCP tools without managed OAuth are routed; use API key or custom OAuth passthrough

### Phase 3: API Center portal for discovery
- [ ] Deploy API Center portal (enterprise-ready MCP registry)
- [ ] Verify MCP servers appear with metadata, descriptions, connection info
- [ ] Test VS Code "Install MCP server" flow from portal (via API Center VS Code extension + `mcp.json`)
- [ ] Configure API Center → Foundry private tool catalog (preview): assign Data Reader RBAC, configure auth under `Governance > Authorization`
- [ ] Show Foundry tool catalog (`Build > Tools`) pulling from API Center

### Phase 4: Agent 365 integration (dependent on GA May 1, 2026)
- [ ] Get preview access for A365 SDK (`Microsoft.Agents.A365.Observability.Runtime` — Python/.NET/JS)
- [ ] Instrument a demo agent with A365 SDK (OpenTelemetry-based wrapping)
- [ ] Show agent registry with tool usage telemetry
- [ ] Demonstrate shadow tool detection (agent calling unregistered tool)
- [ ] Build blast-radius visualization (which agents use which tools)
- [ ] Note: licensing is per user ($15/mo), not per agent. OBO agents covered under user license.

---

## Draft implementation plan — files to create and update

> This section maps the governance plan to specific files in this repo. No code is prescribed — just what needs to exist and what each file should do.

### Existing files that need updates

| File | What exists today | What to change |
|------|-------------------|----------------|
| **`README.md`** | "Coming next: centralized MCP governance" placeholder (line ~155) | Expand into full "MCP Tool Governance Demo" section with capabilities, demo flow, and links to new docs. Update status from "policy XML written, no backend MCP server deployed yet" to reflect demo availability. |
| **`docs/MCP_ONBOARDING.md`** | Complete 3-pattern walkthrough (proxy, expose REST, Foundry auto-route) | Add front-matter linking to the quick demo version. Add "Demo prerequisites" section listing what's pre-configured. Add "Demo automation (future)" section after the talk track. |
| **`docs/ARCHITECTURE.md`** | Has "Unified tool catalog" section with ASCII diagram | Add one line: "See `docs/tools-governance-plan.md` for the full MCP governance architecture and `docs/MCP_DEMO_SCRIPT.md` for the live demo flow." |
| **`docs/TROUBLESHOOTING.md`** | LLM gateway troubleshooting only | Add section: "MCP governance issues" with pointer to `docs/MCP_DEMO_FAQ.md`. |
| **`infra/terraform/modules/apim-config/main.tf`** | Creates backends, products (Alpha/Beta/Gamma), subscriptions, product policies | Add conditional MCP demo infrastructure behind `var.enable_mcp_demo`: new APIM product for MCP access, product policy referencing `mcp-governance.xml`, optional MCP backend resource. |
| **`infra/terraform/modules/apim-config/policies/mcp-governance.xml`** | Rate limiting (10/min tools/call, 60/min tools/list) + correlation ID | Add inline comments for demo narration. Create companion policies: `mcp-governance-strict.xml` (5/min for rate-limit testing), `mcp-governance-auth.xml` (with `validate-azure-ad-token`). |
| **`infra/terraform/modules/api-center/main.tf`** | Creates API Center instance, has manual note about MCP registration | Add comment explaining the sync chain: APIM → API Center → Foundry. Add conditional `azapi_resource` for demo MCP server registration if `enable_mcp_demo=true`. |
| **`infra/terraform/variables.tf`** | APIM, Foundry, monitoring vars | Add `enable_mcp_demo` (bool, default false) and `mcp_demo_backend_url` (string, nullable). |
| **`infra/terraform/outputs.tf`** | Backend pool name, APIM details | Add conditional outputs: `mcp_demo_product_id`, `mcp_demo_subscription_key`. |
| **`scripts/post-deploy.ps1`** | Upgrades product policies post-Foundry API import | Add optional block: "If enable_mcp_demo, apply mcp-governance.xml to MCP product." |
| **`scripts/run_tests.ps1`** | Runs test1–test7 sequentially | Add: run `test_mcp_governance.py` at end if MCP tests exist. |

### New files to create

| File | Purpose | Contents (high level) |
|------|---------|----------------------|
| **`demo/README.md`** | Entry point for MCP governance demo | Overview, prerequisites, how to run each scenario, success criteria, troubleshooting links |
| **`demo/mcp-demo-5min.md`** | Condensed live demo script (5 min) | Exact portal clicks for each step, talk track interleaved, no explanations — just actions. 5 parts: register MCP server (90s), expose API as MCP (60s), apply policy (30s), test in VS Code (60s), show metrics (30s) |
| **`docs/MCP_DEMO_SCRIPT.md`** | Full 10-15 min narration script | Intro (problem statement), 6 live demo parts with timing and slide references, talk track for each, close with summary. Matches the "Demo section plan" in this document. |
| **`docs/MCP_DEMO_FAQ.md`** | Anticipated questions from demo audience | "Why APIM not Foundry?", "What's the difference between mcp-governance.xml and product-alpha.xml?", "When is Agent 365 available?", "Can I test locally?", etc. |
| **`demo/mcp-test-scenarios.md`** | Manual test scenarios for MCP governance | 5 scenarios: rate limiting, correlation ID tracing, method-based limiting (tools/call vs tools/list), session isolation, policy swap |
| **`tests/test_mcp_governance.py`** | Automated test suite for MCP governance | Tests: MCP server connection, rate limiting on tools/call, per-session isolation, X-Correlation-Id presence, policy switching. Dependencies: `requests`, MCP server accessible, subscription key. |
| **`infra/terraform/modules/apim-config/policies/mcp-governance-strict.xml`** | Stricter rate limit policy for demo testing | Same structure as `mcp-governance.xml` but 5 calls/min instead of 30 — makes rate limiting visible in a live demo |
| **`infra/terraform/modules/apim-config/policies/mcp-governance-auth.xml`** | Entra ID auth enforcement policy | Adds `validate-azure-ad-token` with tenant-id and allowed client app IDs — demonstrates auth governance |
| **`scripts/setup-mcp-demo.ps1`** | One-command demo environment setup | Check prerequisites, terraform apply with enable_mcp_demo=true, register MCP server in APIM via CLI, apply policies, run smoke tests, print readiness checklist |
| **`demo/mcp-test-backend.py`** *(optional)* | Minimal local MCP server for testing | FastAPI app exposing MCP JSON-RPC endpoints (tools/list, tools/call). For testing policies without real MCP infrastructure. Can run locally or on Azure Container Apps. |
| **`demo/foundry-agent-demo.py`** | Foundry agent consuming governed tools | Python script using `azure-ai-projects` SDK. Creates a Foundry agent with `McpTool` pointing at APIM gateway URL. Runs a query, shows tool invocation, proves call went through APIM. Based on [`Azure-Samples/foundry-agent-service-remote-mcp-python`](https://github.com/Azure-Samples/foundry-agent-service-remote-mcp-python). |

### Dependency graph

```
README.md (updated)
├── docs/MCP_DEMO_SCRIPT.md          ← Full narration (10-15 min)
│   └── demo/mcp-demo-5min.md        ← Quick version (5 min)
├── docs/tools-governance-plan.md     ← This doc (architecture context)
├── docs/MCP_ONBOARDING.md (updated) ← Reference material
├── docs/MCP_DEMO_FAQ.md             ← Audience Q&A
├── demo/README.md                   ← Demo entry point
│   └── demo/mcp-test-scenarios.md   ← Manual test steps
├── tests/test_mcp_governance.py     ← Automated validation
├── scripts/setup-mcp-demo.ps1       ← Deployment automation
└── Terraform modules (updated)
    ├── apim-config/main.tf          ← MCP product + policy
    ├── apim-config/policies/        ← strict + auth policies
    ├── api-center/main.tf           ← MCP server registration
    └── variables.tf + outputs.tf    ← enable_mcp_demo flag
```

### Execution order

| Order | What | Depends on | Parallelizable |
|-------|------|------------|----------------|
| **1** | Update `infra/terraform/variables.tf`, `outputs.tf` | Nothing | Yes — with steps 2, 3 |
| **2** | Create policy files (`mcp-governance-strict.xml`, `mcp-governance-auth.xml`) | Nothing | Yes |
| **3** | Create `demo/README.md`, `demo/mcp-demo-5min.md`, `demo/mcp-test-scenarios.md` | Nothing | Yes |
| **4** | Update `infra/terraform/modules/apim-config/main.tf` (MCP product) | Step 1 | No |
| **5** | Update `infra/terraform/modules/api-center/main.tf` (sync + registration) | Step 1 | Yes — with step 4 |
| **6** | Create `docs/MCP_DEMO_SCRIPT.md` and `docs/MCP_DEMO_FAQ.md` | Step 3 (uses demo structure) | Yes |
| **7** | Create `scripts/setup-mcp-demo.ps1` | Steps 4, 5 | No |
| **8** | Create `tests/test_mcp_governance.py` | Step 7 (needs infra) | No |
| **9** | Update `README.md`, `docs/ARCHITECTURE.md`, `docs/TROUBLESHOOTING.md` (cross-refs) | Steps 3, 6 | Yes |
| **10** | Update `scripts/post-deploy.ps1`, `scripts/run_tests.ps1` | Steps 7, 8 | Yes |
| **11** | *(Optional)* Create `demo/mcp-test-backend.py` | Nothing | Anytime |
| **12** | *(Post-May 1)* Agent 365 SDK integration | A365 GA | Blocked until May |

---

## Key references

### Microsoft official docs
- [MCP servers in APIM — Overview](https://learn.microsoft.com/en-us/azure/api-management/mcp-server-overview)
- [Expose REST API as MCP server](https://learn.microsoft.com/en-us/azure/api-management/export-rest-mcp-server)
- [Expose existing MCP server via APIM](https://learn.microsoft.com/en-us/azure/api-management/expose-existing-mcp-server)
- [Secure access to MCP servers](https://learn.microsoft.com/en-us/azure/api-management/secure-mcp-servers)
- [Govern MCP tools via AI Gateway (Foundry)](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/tools/governance)
- [Register MCP servers in API Center](https://learn.microsoft.com/en-us/azure/api-center/register-discover-mcp-server)
- [Private tool catalogs for Foundry agents](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/private-tool-catalog)
- [Tool best practices for Foundry Agent Service](https://learn.microsoft.com/en-us/azure/foundry/agents/concepts/tool-best-practice)
- [Configure AI Gateway in Foundry](https://learn.microsoft.com/en-us/azure/foundry/configuration/enable-ai-api-management-gateway-portal)
- [MCP Center — Azure's curated MCP server directory](https://mcp.azure.com/) (not a fully open public registry — curated showcase + private enterprise registry builder)

### Microsoft blog posts & samples
- [APIM as auth gateway for MCP servers](https://techcommunity.microsoft.com/blog/integrationsonazureblog/azure-api-management-your-auth-gateway-for-mcp-servers/4402690)
- [MCP in APIM v2 SKUs + external MCP server support](https://techcommunity.microsoft.com/blog/integrationsonazureblog/new-in-azure-api-management-mcp-in-v2-skus--external-mcp-compliant-server-sup/4440294)
- [Build private MCP registry with API Center](https://techcommunity.microsoft.com/blog/integrationsonazureblog/build-secure-launch-your-private-mcp-registry-with-azure-api-center-/4438016)
- [Expose REST APIs as MCP servers with APIM + API Center](https://techcommunity.microsoft.com/blog/integrationsonazureblog/expose-rest-apis-as-mcp-servers-with-azure-api-management-and-api-center-now-in-/4415013)
- [Secure remote MCP sample (Python/Functions/OAuth)](https://github.com/Azure-Samples/remote-mcp-apim-functions-python)
- [AI Gateway Labs](https://azure-samples.github.io/AI-Gateway/)

### Agent 365
- [Microsoft Agent 365 — product page](https://www.microsoft.com/en-us/microsoft-agent-365)
- [Agent 365 enterprise governance deep-dive (Petri)](https://petri.com/microsoft-agent-365-enterprise-ai-agents/)
- [Agent 365 nears GA (Rob Quickenden)](https://robquickenden.blog/2026/03/agent-365-nears-ga/)
- [Agent 365 security update (RSAC 2026)](https://openclawai.io/blog/microsoft-agent-365-rsac-2026-security-copilot/)

### Internal sources
- CDW A365 Overview meeting transcript (March 13, 2026) — Agent 365 governance, observability, NFRs
- Teams chat (Nick, Jack, Creighton, Jacob) — APIM as governed MCP catalog, Foundry as consumer
- **6 internal SharePoint decks identified:**
  - "Architecting production-ready AI w/ Foundry & AI Gateway" (Mar 11) — APIM as governed MCP proxy
  - "BRK177 — Tools: Where AI Meets the Enterprise" (Feb 12) — Private vs public tool catalog, role-based access
  - "CAIP Roadshow — Azure APIM & MCP" (Mar 2026) — Field enablement: APIM = control plane
  - "OffsiteAIGateways" (Feb 13) — Unified discovery, governance, orchestration
  - "APIM + MCP Presentation" (Mar 2026) — MCP server passthrough, API Center registry
  - "Securing-MCP" (Feb 2) — Security-first MCP registry & gateway patterns
- This repo: `docs/MCP_ONBOARDING.md`, `docs/ARCHITECTURE.md`, `infra/terraform/modules/apim-config/policies/mcp-governance.xml`

---

## Open questions

1. **APIM ↔ API Center sync automation:** The Terraform module deploys API Center but doesn't configure the sync link to APIM. Is this portal-only or scriptable via `az rest`? (Confirmed: sync is one-way APIM→API Center, requires initial configuration, propagates within minutes–24h)
2. **Foundry private tool catalog:** The API Center → Foundry tool catalog integration is in preview. Requires assigning Data Reader RBAC and configuring auth under `Governance > Authorization`. Is this separate from the AI Gateway connection, or does one enable the other?
3. **Agent 365 SDK availability:** A365 SDK is in preview (`Microsoft.Agents.A365.Observability.Runtime 0.2.127-beta`). GA May 1, 2026. Is there a path to get preview access for demo purposes before GA?
4. **MCP managed OAuth limitation:** Foundry AI Gateway currently can't route tools that use managed OAuth. For the demo, use API key auth or custom OAuth passthrough instead. No announced resolution date.
5. **A365 licensing model:** $15/user/month, licensed **per user** (not per agent instance). OBO agents covered under user license. Per-agent-instance licensing is Frontier-only, pricing TBD. For the demo, clarify how many user licenses are needed.

---

## Cross-reference log

*Verified 2026-03-24 against live web sources, Microsoft Learn docs, and internal WorkIQ data.*

### Corrections applied

| Claim | Original | Corrected | Source |
|-------|----------|-----------|--------|
| APIM→API Center sync | "auto-sync" | One-way sync, requires initial configuration, propagates within minutes–24h | MS Learn: synchronize-api-management-apis |
| MCP Center (mcp.azure.com) | "Azure's public MCP registry" | Curated showcase/directory + private enterprise registry builder (not open like npm) | mcp.azure.com/about |
| A365 licensing | "per agent instance" | Per user ($15/mo). OBO agents under user license. Per-agent-instance is Frontier-only, pricing TBD | samexpert.com, licensing.guide |
| A365 "wrapper not framework" | Stated as quote | Internal shorthand, not official messaging. SDK is positioned as "control plane" and "observability SDK" | Web verification — no public source uses this exact framing |
| Agent ↔ tool relationship graphs | "emerging, not GA" | Ships at GA (May 1). Dashboards show agent→tool dependencies, impact chains | microsoft.com/agent-365, smartbridge.com |

### New capabilities added (not in original draft)

| Capability | Source |
|------------|--------|
| A365 lifecycle governance: sponsorship workflows, orphan detection, automated retirement | Petri, MS Agent 365 product page |
| A365 automated circuit breakers: pause agents on anomaly detection | RSAC 2026 coverage |
| A365 SDK in 3 languages: Python, .NET, JavaScript (NuGet 0.2.127-beta) | NuGet registry, MS docs |
| Network-level prompt injection blocking via Entra Internet Access | RSAC 2026 coverage |
| API Center → Foundry private tool catalog (preview): RBAC-gated discovery | MS Learn: private-tool-catalog |
| APIM: 20-tool limit removed, native OAuth 2.1, content safety integration | APIM release notes, Tech Community |
| AI council / gated approval governance pattern | CDW A365 meeting transcript |
| 6 internal enablement decks identified (BRK177, Securing-MCP most relevant) | WorkIQ SharePoint search |

### Internal sources validated

| Source | Finding |
|--------|---------|
| CDW A365 meeting (Mar 13) | APIM as upstream source of truth ✅, "treat agents like users" ✅, AI council/gated approval ✅, mandatory SDK wrapping for production ✅, blast radius awareness ✅ |
| Teams chat (Nick, Jack, Creighton, Jacob) | APIM + API Center = system of record ✅, Foundry as consumer not owner ✅, all tool calls route through APIM ✅, Foundry native MCP governance "preview with gaps" ✅ |
| SharePoint decks | 6 decks confirm APIM-first approach across field enablement, customer narratives, and security patterns |

---

## Phase 2 Execution Plan — MCP Tool Governance Implementation

*Appended 2026-03-24 | For execution agents*

### Live environment (confirmed)

| Resource | Name | Status |
|----------|------|--------|
| Resource Group | `rg-ai-gateway-demo` | ✅ Succeeded |
| APIM | `aigw-apim-b5gl` | ✅ StandardV2, gateway `https://aigw-apim-b5gl.azure-api.net` |
| Foundry (EUS2) | `aigw-foundry-eus2-b5gl` | ✅ AIServices, endpoint confirmed |
| Foundry (SWC) | `aigw-foundry-swc-b5gl` | ✅ AIServices, endpoint confirmed |
| API Center | `aigw-apicenter-b5gl` | ✅ East US, 1 test API (Petstore), no MCP servers |
| LLM API | `foundry-ai-gateway` on `/openai` | ✅ Working, GPT-5.1 responds |
| Products | team-alpha, team-beta, team-gamma | ✅ All published |
| Backends | eus2 + swc + pool | ✅ MI auth, circuit breakers |
| MCP Servers | None | 🔲 Clean slate — this is what we're building |
| Subscription | `ME-MngEnvMCAP274809-nsangeorge-1` | ✅ `b68da7d5-0cd1-456c-af93-79733d55d2ae` |

### Scope: what's IN vs OUT

| IN (building now) | OUT (deferred) |
|--------------------|----------------|
| Register MCP server in APIM (Microsoft Learn) | Agent 365 SDK integration (GA May 1) |
| Expose Echo API as MCP server | A365 agent registry/dashboard |
| Apply `mcp-governance.xml` policy | Shadow AI detection |
| MCP product + subscription in Terraform | Per-agent-instance licensing |
| API Center ↔ APIM sync link | |
| Register MCP servers in API Center | |
| Foundry AI Gateway connection to APIM | |
| Foundry agent demo (`demo/foundry-agent-demo.py`) | |
| MCP governance tests | |
| Demo docs + scripts | |
| `setup-mcp-demo.ps1` automation script | |
| Policy variants (strict, auth) | |
| Update README + cross-ref docs | |

### Execution waves

Work is organized into 4 waves. Each wave can have parallel work items within it. Waves are sequential — wave N+1 starts after wave N completes.

---

#### Wave 1: Infrastructure foundation (no Azure side effects)

All file changes. No `terraform apply`, no `az` commands. Pure code/docs. **All items parallelizable.**

| ID | Todo | Files | What to do | Depends on |
|----|------|-------|------------|------------|
| **W1-A** | Add Terraform variables for MCP demo | `infra/terraform/variables.tf`, `infra/terraform/outputs.tf` | Add `enable_mcp_demo` (bool, default false), `mcp_server_url` (string, nullable). Add conditional outputs `mcp_demo_product_id`, `mcp_demo_subscription_key`. | Nothing |
| **W1-B** | Add MCP product + backend to apim-config | `infra/terraform/modules/apim-config/variables.tf`, `infra/terraform/modules/apim-config/main.tf`, `infra/terraform/modules/apim-config/outputs.tf` | Add `enable_mcp_demo` and `mcp_server_url` variables. Add conditional `azurerm_api_management_product` "mcp-servers" with `mcp-governance.xml` as product policy. Add conditional `azapi_resource` backend for MCP server URL. Wire through from root `main.tf`. Export MCP subscription key. | Nothing |
| **W1-C** | Create policy variants | `infra/terraform/modules/apim-config/policies/mcp-governance-strict.xml`, `infra/terraform/modules/apim-config/policies/mcp-governance-auth.xml` | Strict: copy `mcp-governance.xml` but 5 calls/min for tools/call (makes rate limiting visible in demo). Auth: add `validate-azure-ad-token` block with parameterized tenant-id. | Nothing |
| **W1-D** | Create demo directory + docs | `demo/README.md`, `demo/mcp-demo-5min.md`, `demo/mcp-test-scenarios.md` | Demo README: overview, prerequisites (az login, APIM running, subscription key), how to run. 5-min demo: exact portal steps condensed. Test scenarios: 5 manual test descriptions (rate limit, correlation ID, method-based limit, session isolation, policy swap). | Nothing |
| **W1-E** | Create full demo narration + FAQ | `docs/MCP_DEMO_SCRIPT.md`, `docs/MCP_DEMO_FAQ.md` | 10-15 min narration script matching the "Demo section plan" in this doc. FAQ: 8-10 anticipated questions with answers. | Nothing |

---

#### Wave 2: Automation scripts + Foundry agent demo (depends on Wave 1)

Scripts that automate setup and the Foundry agent demo script. **All items parallelizable.**

| ID | Todo | Files | What to do | Depends on |
|----|------|-------|------------|------------|
| **W2-A** | Create MCP demo setup script | `scripts/setup-mcp-demo.ps1` | PowerShell script that: (1) reads terraform outputs; (2) registers Microsoft Learn MCP server in APIM via portal REST API (`az rest PUT .../mcpServers/microsoft-learn`); (3) exposes Echo API as MCP server; (4) applies `mcp-governance.xml` policy to MCP servers; (5) creates MCP product subscription; (6) links API Center to APIM if not linked; (7) registers MCP servers in API Center; (8) prints readiness checklist. Use existing `post-deploy.ps1` as the pattern for `az rest` calls. Target APIM: `aigw-apim-b5gl`, RG: `rg-ai-gateway-demo`, subscription: `b68da7d5-0cd1-456c-af93-79733d55d2ae`. | W1-A, W1-B |
| **W2-B** | Create Foundry agent demo | `demo/foundry-agent-demo.py`, `demo/requirements.txt` | Python script using `azure-ai-projects` SDK. Creates a Foundry agent with `McpTool` pointing at `https://aigw-apim-b5gl.azure-api.net/<mcp-path>/mcp`. Configurable via env vars: `AIGW_GATEWAY_URL`, `AIGW_MCP_KEY`, `AZURE_FOUNDRY_ENDPOINT`, `MODEL_NAME`. Runs a query that triggers the tool, prints result + shows tool was invoked. Based on pattern from `Azure-Samples/foundry-agent-service-remote-mcp-python`. Include requirements.txt with `azure-ai-projects>=1.0.0`. | W1-D (needs to know the MCP server path) |
| **W2-C** | Create MCP governance tests | `tests/test_mcp_governance.py`, `tests/test_mcp_rate_limit.py` | Test suite using `requests` library (not OpenAI SDK — MCP uses JSON-RPC, not OpenAI format). `test_mcp_governance.py`: test MCP server connectivity through APIM, verify X-Correlation-Id header in response, verify tools/list returns tool definitions. `test_mcp_rate_limit.py`: rapid-fire tools/call requests, verify 429 after threshold, verify per-session isolation (two different Mcp-Session-Id values have independent counters), verify tools/list has higher limit than tools/call. Tests read env vars from `scripts/set_env.ps1` pattern. Target: `https://aigw-apim-b5gl.azure-api.net/<mcp-path>/mcp`. | W1-A (needs MCP product subscription key pattern) |

---

#### Wave 3: Validation guide (depends on Wave 2)

Manual validation by Nick. Agents create the validation doc; Nick runs it end-to-end after `tf destroy` + fresh deploy.

| ID | Todo | Files | What to do | Depends on |
|----|------|-------|------------|------------|
| **W3-VAL** | Create end-to-end validation guide | `docs/VALIDATION_MCP.md` | Step-by-step guide for manual end-to-end validation. Covers: (1) `terraform destroy` existing env; (2) `terraform apply` with `enable_mcp_demo=true` and `mcp_server_url`; (3) manual portal step: import Foundry API (same as Phase 1); (4) run `scripts/post-deploy.ps1` (Phase 1 baseline); (5) run Phase 1 tests (`scripts/run_tests.ps1`) to confirm baseline still works; (6) run `scripts/setup-mcp-demo.ps1` (register MCP servers, apply policies, link API Center); (7) run MCP governance tests (`tests/test_mcp_governance.py`, `tests/test_mcp_rate_limit.py`); (8) run Foundry agent demo (`demo/foundry-agent-demo.py`); (9) verify API Center shows MCP servers; (10) verify APIM metrics show MCP requests. Include expected outputs at each step, common errors + fixes, and a final "✅ all green" checklist. Can reference/extend existing QUICKSTART.md structure. | W2-A, W2-B, W2-C |

---

#### Wave 4: Polish + integration (depends on Wave 3)

Update existing docs, wire everything together. **All items parallelizable.**

| ID | Todo | Files | What to do | Depends on |
|----|------|-------|------------|------------|
| **W4-A** | Update README.md | `README.md` | Replace "Coming next: centralized MCP governance" (lines 155-169) with full "MCP Tool Governance Demo" section. Link to `docs/MCP_DEMO_SCRIPT.md`, `demo/README.md`. Update status. Keep it concise — 15-20 lines max, link out for details. | W3-C (need confirmed test results) |
| **W4-B** | Update existing docs (cross-refs) | `docs/ARCHITECTURE.md`, `docs/TROUBLESHOOTING.md`, `docs/MCP_ONBOARDING.md` | ARCHITECTURE: add one-liner linking to MCP demo script. TROUBLESHOOTING: add "MCP governance issues" section pointing to FAQ. MCP_ONBOARDING: add front-matter about demo prerequisites. | W3-C |
| **W4-C** | Update test/script runners | `scripts/run_tests.ps1`, `scripts/set_env.ps1` | run_tests: add MCP test execution at end (conditional on MCP product existing). set_env: add `AIGW_MCP_KEY`, `AIGW_MCP_URL` env vars from terraform output. | W3-C |
| **W4-D** | Update post-deploy.ps1 | `scripts/post-deploy.ps1` | Add optional section at end: "If MCP demo enabled, apply mcp-governance.xml policy to MCP servers." Follow existing pattern of `az rest PUT` for policy application. Guard with check for MCP product existence. | W3-B |

---

### Agent dispatch guide

When dispatching execution agents, use these wave assignments. Each agent gets:
1. The specific todo ID and files
2. The live environment details (APIM name, RG, subscription ID, gateway URL) for reference in scripts/tests
3. Instructions to read existing files before modifying (use same patterns)
4. Instructions to update todo status in SQL when done

**Wave 1 dispatch:** 5 parallel agents (W1-A through W1-E)
**Wave 2 dispatch:** 3 parallel agents (W2-A through W2-C)
**Wave 3 dispatch:** 1 agent — creates VALIDATION_MCP.md (W3-VAL)
**Wave 4 dispatch:** 4 parallel agents (W4-A through W4-D)

**After Wave 4:** Nick runs manual validation using VALIDATION_MCP.md: `tf destroy` → fresh `tf apply` with `enable_mcp_demo=true` → full end-to-end validation.

### Validation criteria

The implementation is complete (agent work done) when:

1. ✅ `terraform plan -var="enable_mcp_demo=true"` shows only additive changes (no destroys)
2. ✅ All new policy XML files are valid and follow existing patterns
3. ✅ `setup-mcp-demo.ps1` is written and follows `post-deploy.ps1` conventions
4. ✅ MCP governance tests are written and cover rate limiting, correlation IDs, session isolation
5. ✅ Foundry agent demo script exists with clear env var configuration
6. ✅ Demo docs (5-min, full narration, FAQ) are complete and consistent
7. ✅ `VALIDATION_MCP.md` provides clear end-to-end manual validation steps
8. ✅ README.md reflects the MCP demo capability
9. ✅ All cross-reference docs are updated

Nick validates manually (using VALIDATION_MCP.md):
- `tf destroy` → `tf apply` → portal import → `post-deploy.ps1` → Phase 1 tests pass → `setup-mcp-demo.ps1` → MCP tests pass → Foundry agent demo works → API Center shows MCP servers

### Risk register

| Risk | Impact | Mitigation |
|------|--------|------------|
| MCP server registration via REST API may have undocumented API version | W3-B blocks | Fall back to portal registration, document the manual step |
| Foundry agent SDK may not have `McpTool` class available | W3-D blocks | Fall back to direct `requests` calls to APIM MCP endpoint, still proves governance works |
| API Center ↔ APIM sync link may not be scriptable | W3-E blocks | Register MCP servers in API Center manually or via `az rest` directly to API Center |
| `mcp-governance.xml` policy may fail on MCP server API type | W3-B blocks | Test policy application separately, adjust XML if MCP API type has different policy schema |
| Terraform conditional resources may conflict with existing state | W3-A blocks | Run `terraform plan` first, review carefully before apply. All new resources are `count = var.enable_mcp_demo ? 1 : 0` |
