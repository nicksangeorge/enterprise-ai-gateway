# MCP Tool Governance — Live Demo Script

**Duration:** 10-15 minutes
**Audience:** Platform engineering leads, enterprise architects, security/governance teams
**Prerequisites:** Deployed APIM instance with AI Gateway, API Center, at least one MCP server registered. See [QUICKSTART.md](QUICKSTART.md) and [MCP_ONBOARDING.md](MCP_ONBOARDING.md).

---

## Part 1: The problem

**[TIMING: 2 minutes]**

**[ACTION: Show slide — "Before: ungoverned tool access"]**

The slide should depict: 5 teams, 12 agents, 30+ tools. Each agent has hardcoded MCP server URLs pointing directly at external services. No central catalog. No auth consistency. No audit trail. Lines crossing everywhere — spaghetti.

**[TALK TRACK]**

> "Here's what most enterprises look like today with agent tooling. Five teams, twelve agents, thirty-plus tools. Each team wired up their own MCP servers. Some use API keys, some use OAuth, some use nothing. Nobody knows which agents are calling which tools. There's no rate limiting, no audit trail, and no way to answer the question: 'If this MCP server goes down, what breaks?'
>
> This is the same problem we solved for APIs ten years ago with API Management. Agents just brought it back."

**[EXPECTED: Audience recognizes the sprawl pattern from their own orgs]**

---

## Part 2: Register tools in APIM

**[TIMING: 3 minutes]**

### 2a: Proxy an existing MCP server (~90 seconds)

**[ACTION: Azure portal → APIM instance → APIs → MCP Servers → + Create MCP server → "Expose an existing MCP server"]**

Fill in:

| Field | Value |
|---|---|
| MCP server base URL | `https://learn.microsoft.com/api/mcp` |
| Transport type | Streamable HTTP |
| Name | `microsoft-learn` |
| Base path | `learn` |
| Description | Microsoft Learn documentation search |

Click **Create**.

**[EXPECTED: MCP server appears in the list. Server URL: `https://aigw-apim.azure-api.net/learn/mcp`]**

**[TALK TRACK]**

> "Microsoft Learn has a public MCP server. Instead of letting every agent call it directly, we register it through APIM. Four fields, click Create. Now every call to this tool goes through our gateway — same portal your APIM teams already use."

### 2b: Expose a REST API as MCP (~60 seconds)

**[ACTION: Azure portal → APIM → APIs → MCP Servers → + Create MCP server → "Expose an API as an MCP server"]**

Select the **Echo API** (built-in). Pick a couple of operations to expose as tools. Name it `echo-tools`.

**[EXPECTED: Each selected operation becomes an MCP tool. APIM generates tool definitions from the OpenAPI spec.]**

**[TALK TRACK]**

> "What if you already have REST APIs in APIM? You don't need to build an MCP server. APIM exposes your existing operations as MCP tools. The OpenAPI spec becomes the tool definition. Agents can call them the same way they call any MCP server."

---

## Part 3: Apply governance policies

**[TIMING: 2 minutes]**

**[ACTION: Select the `microsoft-learn` MCP server → MCP → Policies. Paste the policy XML.]**

Show `mcp-governance.xml` from the repo (`infra/terraform/modules/apim-config/policies/mcp-governance.xml`):

```xml
<policies>
    <inbound>
        <base />
        <set-header name="X-Correlation-Id" exists-action="override">
            <value>@(context.RequestId)</value>
        </set-header>
        <set-variable name="body"
            value="@(context.Request.Body.As<string>(preserveContent: true))" />
        <choose>
            <!-- tools/call = write operation → strict rate limit -->
            <when condition="@{
                var body = (string)context.Variables[&quot;body&quot;];
                var json = Newtonsoft.Json.Linq.JObject.Parse(body);
                var method = json[&quot;method&quot;]?.ToString() ?? &quot;&quot;;
                return method == &quot;tools/call&quot;;
            }">
                <rate-limit-by-key calls="10" renewal-period="60"
                    counter-key="@(context.Request.Headers
                        .GetValueOrDefault(&quot;Mcp-Session-Id&quot;, &quot;unknown&quot;))" />
            </when>
            <!-- Everything else (tools/list, initialize) → generous limit -->
            <otherwise>
                <rate-limit-by-key calls="60" renewal-period="60"
                    counter-key="@(context.Request.Headers
                        .GetValueOrDefault(&quot;Mcp-Session-Id&quot;, &quot;unknown&quot;))" />
            </otherwise>
        </choose>
    </inbound>
    ...
</policies>
```

**[TALK TRACK]**

> "One policy file. It parses the JSON-RPC body and differentiates between `tools/call` — an actual tool invocation — and `tools/list`, which is just discovery. Write operations get 10 per minute per session. Read operations get 60. Every request gets a correlation ID for end-to-end tracing.
>
> This is the same APIM policy language teams already know. No new framework, no new SDK. You apply it in the portal and it's live."

**[EXPECTED: Policy saved. Green checkmark in the portal.]**

---

## Part 4: Discover tools in API Center

**[TIMING: 2 minutes]**

**[ACTION: Navigate to API Center in the Azure portal. Show the catalog view.]**

**[EXPECTED: MCP servers registered in APIM appear in API Center. Each entry shows name, description, connection info, and which governance policies apply.]**

**[TALK TRACK]**

> "API Center is the discovery surface. APIM syncs registered MCP servers here automatically. Developers browse this catalog, find tools, get connection info — without needing access to the APIM management plane."

**[ACTION: Switch to Foundry portal → Build → Tools]**

**[EXPECTED: The same tools appear in Foundry's tool catalog, pulled from API Center via the private tool catalog integration.]**

**[TALK TRACK]**

> "Same tools show up in Foundry's tool catalog. One catalog, three registration paths: proxy an external MCP server, expose a REST API, or register directly in API Center. Every agent — Foundry, custom, third-party — discovers the same set of governed tools."

---

## Part 5: Foundry agent consumes governed tool

**[TIMING: 3 minutes]**

### 5a: Show the agent code

**[ACTION: Open `demo/foundry-agent-demo.py` (or equivalent) in the editor. Highlight the key lines.]**

```python
from azure.ai.projects import AgentsClient, McpTool

mcp_tool = McpTool(
    server_label="learn-search",
    server_url="https://aigw-apim.azure-api.net/learn/mcp",
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

**[TALK TRACK]**

> "Here's a Foundry agent. The only thing that matters is line 4: `server_url` points at APIM, not at `learn.microsoft.com` directly. The agent doesn't know it's governed. It just calls a URL."

### 5b: Run the agent

**[ACTION: Run the script. Send a query like "Search Microsoft Learn for APIM rate limiting best practices."]**

**[EXPECTED: Agent invokes the Learn search tool, returns documentation results. Normal operation.]**

**[TALK TRACK]**

> "The agent calls the tool, gets results. Works exactly as if it were calling the MCP server directly."

### 5c: Show APIM metrics

**[ACTION: Azure portal → APIM → Monitoring → Metrics. Show requests for the MCP server API.]**

**[EXPECTED: 200 status codes appear for the MCP server. Correlation IDs visible in the logs.]**

**[TALK TRACK]**

> "Over in APIM, we can see the request. 200, correlation ID, session ID, timestamp. Same observability you get for any APIM-managed API."

### 5d: Trigger rate limit

**[ACTION: Run rapid-fire tool calls — a loop sending 15+ requests in under a minute.]**

**[EXPECTED: First 10 succeed (200). Subsequent calls return 429 Too Many Requests.]**

**[TALK TRACK]**

> "Now I'm hammering the tool. After 10 calls in a minute, APIM returns 429. The agent gets an error it can handle — retry, back off, or surface it to the user. The MCP server itself never saw those excess requests. That's the governance layer doing its job.
>
> The agent didn't know it was governed. It called a URL. APIM handled auth, rate limits, and logging transparently."

---

## Part 6: Enforcement model

**[TIMING: 2 minutes]**

**[ACTION: Show slide — the prevention/detection enforcement stack]**

The slide should show this two-layer diagram:

```
┌──────────────────────────────────────────────────┐
│  LAYER 1: PREVENTION (hard enforcement)          │
│                                                  │
│  Foundry:   Private tool catalog + RBAC lockdown │
│  Network:   NSG/firewall → outbound only to APIM │
│  APIM:      Auth, rate limits, IP filtering      │
│  Pipeline:  Allowlist scan in CI/CD              │
│  GHCP:      Enterprise admin MCP server policy   │
└──────────────────────┬───────────────────────────┘
                       │ some things get through
                       ▼
┌──────────────────────────────────────────────────┐
│  LAYER 2: DETECTION (soft enforcement)           │
│                                                  │
│  Agent 365:  Shadow AI detection                 │
│  Agent 365:  Tool usage tracing (all calls)      │
│  Agent 365:  Anomaly → automated circuit breaker │
│  APIM logs:  Unrecognized endpoint alerts        │
└──────────────────────────────────────────────────┘
```

**[TALK TRACK]**

> "Can someone bypass this? In dev, yes. In production, you layer your defenses.
>
> Layer 1 is prevention. Foundry's private tool catalog with RBAC means developers only see approved tools. Network controls block outbound to anything except APIM. CI/CD pipelines scan for unauthorized MCP server URLs and block the PR. GitHub Copilot enterprise admin policies control which MCP servers are available to coding agents.
>
> Layer 2 is detection. Agent 365 traces every tool invocation — approved or not. Shadow AI detection via Entra Internet Access flags agents calling tools outside the catalog. Automated circuit breakers can pause agents on anomaly detection.
>
> Prevention where possible. Detection everywhere else."

**[EXPECTED: Audience understands this is a layered model, not a single killswitch.]**

---

## Close: Summary

**[TIMING: 1 minute]**

**[ACTION: Show summary slide with three pillars]**

| Component | Role |
|-----------|------|
| **APIM** | Functional control plane — auth, rate limits, routing, logging |
| **API Center** | Discovery surface — one catalog, three registration paths |
| **Agent 365** | Non-functional governance — identity, observability, compliance (GA May 2026) |

**[TALK TRACK]**

> "Three components, one governance layer.
>
> APIM is the functional control plane. It handles auth, rate limits, and logging for every tool call. It's agent-agnostic — Foundry agents, custom agents, partner agents, coding agents all hit the same gateway.
>
> API Center is the discovery surface. One catalog where every team finds the same governed tools.
>
> Agent 365 is the non-functional layer. It tells you which agents are using which tools, what the blast radius is when something changes, and whether anyone is using unapproved tools. GA May 2026.
>
> Together: one governance layer for everything."

---

## Quick reference: demo flow

| Part | Duration | What you show | Key artifact |
|------|----------|---------------|-------------|
| 1. The problem | 2 min | Slide: ungoverned sprawl | — |
| 2. Register tools | 3 min | Portal: proxy MCP + expose REST as MCP | APIM MCP Servers blade |
| 3. Apply policies | 2 min | Portal: paste `mcp-governance.xml` | `mcp-governance.xml` |
| 4. Discover in API Center | 2 min | Portal: API Center catalog + Foundry tools | API Center, Foundry Build > Tools |
| 5. Agent consumes tool | 3 min | Code + run + metrics + 429 | `foundry-agent-demo.py` |
| 6. Enforcement model | 2 min | Slide: prevention/detection stack | — |
| Close | 1 min | Slide: three pillars | — |

**Total: ~13 minutes** (leaves buffer for questions during the demo)

---

## Pre-demo checklist

- [ ] APIM instance deployed and accessible
- [ ] At least one MCP server registered (Microsoft Learn proxy)
- [ ] `mcp-governance.xml` policy applied
- [ ] API Center synced with APIM
- [ ] Foundry agent demo script tested end-to-end
- [ ] APIM metrics blade open in a browser tab
- [ ] Slides ready: problem slide, enforcement stack slide, summary slide
- [ ] Subscription key available for live demo
- [ ] Backup screenshots in case of portal latency
