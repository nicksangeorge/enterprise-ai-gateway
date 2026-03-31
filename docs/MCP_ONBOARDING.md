# Onboarding MCP servers through APIM

**Prerequisites:**
- Azure subscription with Owner or Contributor role
- APIM instance (Standard v2 tier or higher) deployed and running
- Foundry AI Gateway enabled (portal step in [QUICKSTART.md](QUICKSTART.md) Part 3)
- VS Code with Copilot extension for testing (optional but recommended)
- External MCP server endpoint (for Pattern 1) or existing REST API in APIM (for Pattern 2)

This walkthrough covers Part 5 of the demo: registering real MCP servers through APIM AI Gateway and applying governance policies. It demonstrates the enterprise workflow for tool onboarding.

## What we're demonstrating

Three patterns for MCP governance:

1. **Proxy an existing remote MCP server** through APIM (Microsoft Learn MCP)
2. **Expose a managed REST API** as an MCP server in APIM
3. **Foundry-managed tools** auto-routing through APIM

---

## Pattern 1: Proxy an existing MCP server

This registers an external MCP server (Microsoft Learn) behind APIM so all calls go through your governance layer.

### Step 1: Register the server

In the Azure portal, open your APIM instance. Navigate to **APIs** > **MCP Servers** > **+ Create MCP server**.

Select **Expose an existing MCP server**.

Fill in:

| Field | Value |
|---|---|
| **MCP server base URL** | `https://learn.microsoft.com/api/mcp` |
| **Transport type** | Streamable HTTP (default) |
| **Name** | `microsoft-learn` |
| **Base path** | `learn` |
| **Description** | Microsoft Learn documentation search and retrieval |

Select **Create**.

The MCP server appears in the list with a Server URL like:
`https://aigw-apim.azure-api.net/learn/mcp`

### Step 2: Apply governance policies

Select the MCP server from the list. Go to **MCP** > **Policies**.

Add this policy (rate limit per MCP session + correlation ID):

```xml
<policies>
    <inbound>
        <base />
        <!-- Rate limit: 30 tool calls per minute per session -->
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
        <!-- Correlation ID for request tracing -->
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

What this does:

- Rate limiting: 30 `tools/call` requests per minute, keyed by MCP session ID. Other JSON-RPC methods (like `tools/list`) pass through unrestricted.
- Correlation ID: tags every request with the APIM request ID so you can trace tool calls across the full request path in logs.

### Step 3: Test with VS Code

In VS Code, use the **MCP: Add Server** command. Set:

- **Server type**: HTTP
- **Server URL**: `https://aigw-apim.azure-api.net/learn/mcp`
- **Header**: `api-key` with your APIM subscription key

Switch to Copilot agent mode. Select the tools from the MCP server. Ask it something like:

> "Search Microsoft Learn for Azure API Management AI Gateway setup."

You should see the tool call go through and return results from Microsoft Learn docs.

### Step 4: Verify governance

In the Azure portal, check **APIM** > **Monitoring** > **Metrics**. You should see requests for the MCP server API.

Look for:

- 200s: successful tool calls
- 429s: rate limit triggered (try rapid-fire calls to confirm)

For detailed tracing, go to **Monitoring** > **Logs** and query by the `X-Correlation-Id` header value.

---

## Pattern 2: Expose a REST API as MCP server

If you have an existing REST API managed in APIM, you can expose it as an MCP-compliant server. APIM handles the protocol translation; the original API stays unchanged.

### Step 1: Import or identify the REST API

You need a REST API already managed in APIM. For the demo, use the built-in Echo API or import a simple API.

If you need to import one: **APIs** > **+ Add API** > pick your format (OpenAPI, etc.).

### Step 2: Create the MCP server

Navigate to **APIs** > **MCP Servers** > **+ Create MCP server**.

Select **Expose an API as an MCP server**.

| Field | Value |
|---|---|
| **API** | Select the managed API |
| **Operations** | Pick which operations to expose as tools |
| **Name** | e.g., `enterprise-tools` |

Each selected API operation becomes an MCP tool that agents can call. APIM generates the tool definitions from your API's OpenAPI spec: names, descriptions, input schemas all carry over.

### Step 3: Apply governance policies

Same pattern as Pattern 1: rate limiting by session, correlation IDs, logging. Copy the policy XML from above and adjust the rate limits to match the API's capacity.

### Step 4: Test the same way

Add the new MCP server URL to VS Code, same as Pattern 1. The tools show up with names derived from your API operations.

---

## Talk track for the demo

> "Here's the enterprise workflow for tool governance. A new MCP server appears, maybe a team built it, maybe it's a third-party service. The platform team registers it through APIM in about two minutes. They apply governance policies: rate limits, logging, correlation IDs. Now every team can discover it, and every call flows through the same dashboard. No custom code, no per-tool configuration on the consumer side."

> "And if a tool is registered in Microsoft Foundry? Same thing, it auto-routes through APIM when AI Gateway is enabled. One governance layer for everything."

Key points to hit:

- Two minutes to onboard. Registration is a few fields in the portal.
- Policies apply uniformly. Same XML policy language APIM teams already know.
- Observability included. Metrics, logs, and tracing work without extra setup.
- No client-side changes. Consumers just point at the APIM URL.

---

## Next step: API Center catalog

After registering MCP servers in APIM, sync them to API Center for org-wide discovery. See the API Center setup in the Terraform module (`tf-api-center` todo).

In the API Center portal, developers can:

- Browse available MCP tools with descriptions
- Get connection info (URLs, auth requirements)
- See which governance policies apply

All without needing access to the APIM management plane.
