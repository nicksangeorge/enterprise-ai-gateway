# MCP Governance Demo — 5-Minute Script

Portal clicks + talk track. No explanations. Go.

> **APIM gateway URL used in this script:** `https://aigw-apim-b5gl.azure-api.net`
> Replace with your own APIM instance URL.

---

## Part 1: Register Microsoft Learn MCP server (90s)

1. Open Azure portal → navigate to your APIM instance
2. Left nav: **APIs** → **MCP Servers**
3. Click **+ Create MCP server**
4. Select **Expose an existing MCP server**
5. Fill in:

| Field | Value |
|-------|-------|
| MCP server base URL | `https://learn.microsoft.com/api/mcp` |
| Transport type | Streamable HTTP (default) |
| Name | `microsoft-learn` |
| Base path | `learn` |
| Description | Microsoft Learn documentation search |

6. Click **Create**
7. Server appears in the list. Note the Server URL: `https://aigw-apim-b5gl.azure-api.net/learn/mcp`

**Talk track:** *"Ninety seconds to register an external MCP server. Every call now goes through APIM — auth, rate limits, logging, all applied before the request hits the backend."*

---

## Part 2: Expose Echo API as MCP (60s)

1. Still in APIM → **APIs** → **MCP Servers**
2. Click **+ Create MCP server**
3. Select **Expose an API as an MCP server**
4. Fill in:

| Field | Value |
|-------|-------|
| API | Select **Echo API** |
| Operations | Pick all operations (or select specific ones) |
| Name | `echo-tools` |

5. Click **Create**
6. Each selected operation is now an MCP tool. Agents can call them via JSON-RPC.

**Talk track:** *"Any REST API already in APIM can become an MCP server. APIM generates tool definitions from the OpenAPI spec. No code changes."*

---

## Part 3: Apply governance policy (30s)

1. In the MCP Servers list, click the **microsoft-learn** server
2. Go to **MCP** → **Policies**
3. Paste this policy XML:

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
                    calls="10"
                    renewal-period="60"
                    counter-key="@(context.Request.Headers.GetValueOrDefault(&quot;Mcp-Session-Id&quot;, &quot;unknown&quot;))" />
            </when>
            <when condition="@(
                Newtonsoft.Json.Linq.JObject.Parse((string)context.Variables[&quot;body&quot;])[&quot;method&quot;] != null
                && Newtonsoft.Json.Linq.JObject.Parse((string)context.Variables[&quot;body&quot;])[&quot;method&quot;].ToString() == &quot;tools/list&quot;
            )">
                <rate-limit-by-key
                    calls="60"
                    renewal-period="60"
                    counter-key="@(context.Request.Headers.GetValueOrDefault(&quot;Mcp-Session-Id&quot;, &quot;unknown&quot;))" />
            </when>
        </choose>
        <set-header name="X-Correlation-Id" exists-action="override">
            <value>@(context.RequestId)</value>
        </set-header>
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <base />
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>
```

4. Click **Save**

**Talk track:** *"One policy file. Rate limits by method — 10 tool calls per minute, 60 list requests per minute, each scoped to the MCP session. Correlation ID on every request for tracing."*

---

## Part 4: Test in VS Code (60s)

1. Open VS Code
2. `Ctrl+Shift+P` → **MCP: Add Server**
3. Select **HTTP**
4. Server URL: `https://aigw-apim-b5gl.azure-api.net/learn/mcp`
5. Add header: `api-key` → paste your APIM subscription key
6. Switch to **Copilot agent mode** (click the model picker → Agent)
7. Select the MCP tools from the server
8. Ask: *"Search Microsoft Learn for Azure API Management MCP server setup"*
9. Watch the tool call execute and return results

**Talk track:** *"The agent doesn't know it's governed. It calls a URL. APIM handled auth, rate limits, and logging transparently. Same endpoint works for Foundry agents, VS Code, custom agents — anything that speaks MCP."*

---

## Part 5: Show metrics (30s)

1. Back in Azure portal → APIM instance
2. Left nav: **Monitoring** → **Metrics**
3. Metric: **Requests**
4. Split by: **API Name**
5. Look for:
   - **200s** — successful tool calls
   - **429s** — rate limit triggered (rapid-fire calls to demonstrate)

**Talk track:** *"Every call is tracked. Same dashboard you use for LLM governance now covers tool governance. One control plane for everything."*

---

## End-to-end timing

| Part | Duration | What you show |
|------|----------|---------------|
| 1 | 90s | Register external MCP server |
| 2 | 60s | Expose REST API as MCP |
| 3 | 30s | Apply governance policy |
| 4 | 60s | Test from VS Code |
| 5 | 30s | Metrics dashboard |
| **Total** | **~4.5 min** | |
