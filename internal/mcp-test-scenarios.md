# MCP Governance — Manual Test Scenarios

5 scenarios to verify MCP governance policies work as expected.

> **APIM gateway URL:** `https://aigw-apim-b5gl.azure-api.net`
> Replace with your own APIM instance URL throughout.

> **Prerequisites for all scenarios:**
> - APIM instance deployed with MCP server registered (see [demo README](README.md))
> - Governance policy applied (see [mcp-demo-5min.md](mcp-demo-5min.md), Part 3)
> - Valid APIM subscription key (`$API_KEY` in examples below)

---

## Scenario 1: Rate limiting on `tools/call`

**What:** Send >10 `tools/call` JSON-RPC requests within 60 seconds using the same session ID. The policy limits `tools/call` to 10 per minute per session.

**Expected:** Requests 1–10 return 200. Request 11+ returns 429.

**Command (PowerShell):**

```powershell
$headers = @{
    "Content-Type" = "application/json"
    "api-key" = "$API_KEY"
    "Mcp-Session-Id" = "test-session-001"
}

$body = @{
    jsonrpc = "2.0"
    method = "tools/call"
    params = @{
        name = "search"
        arguments = @{ query = "test" }
    }
    id = 1
} | ConvertTo-Json -Depth 5

# Send 12 requests rapidly
1..12 | ForEach-Object {
    $response = Invoke-WebRequest -Uri "https://aigw-apim-b5gl.azure-api.net/learn/mcp" `
        -Method POST -Headers $headers -Body $body -SkipHttpErrorAction
    Write-Host "Request $_`: $($response.StatusCode)"
}
```

**Command (curl):**

```bash
for i in $(seq 1 12); do
  echo -n "Request $i: "
  curl -s -o /dev/null -w "%{http_code}" \
    -X POST "https://aigw-apim-b5gl.azure-api.net/learn/mcp" \
    -H "Content-Type: application/json" \
    -H "api-key: $API_KEY" \
    -H "Mcp-Session-Id: test-session-001" \
    -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"search","arguments":{"query":"test"}},"id":1}'
  echo
done
```

**How to verify:**
- Requests 1–10: HTTP 200
- Requests 11–12: HTTP 429 with `retry-after` header
- In APIM portal: **Monitoring** → **Metrics** → filter by API name, confirm 429 count matches

---

## Scenario 2: Rate limiting on `tools/list`

**What:** Send >60 `tools/list` requests within 60 seconds using the same session ID. The policy limits `tools/list` to 60 per minute per session.

**Expected:** Requests 1–60 return 200. Request 61+ returns 429.

**Command (curl):**

```bash
for i in $(seq 1 65); do
  echo -n "Request $i: "
  curl -s -o /dev/null -w "%{http_code}" \
    -X POST "https://aigw-apim-b5gl.azure-api.net/learn/mcp" \
    -H "Content-Type: application/json" \
    -H "api-key: $API_KEY" \
    -H "Mcp-Session-Id: test-session-002" \
    -d '{"jsonrpc":"2.0","method":"tools/list","id":1}'
  echo
done
```

**Command (PowerShell):**

```powershell
$headers = @{
    "Content-Type" = "application/json"
    "api-key" = "$API_KEY"
    "Mcp-Session-Id" = "test-session-002"
}

$body = '{"jsonrpc":"2.0","method":"tools/list","id":1}'

1..65 | ForEach-Object {
    $response = Invoke-WebRequest -Uri "https://aigw-apim-b5gl.azure-api.net/learn/mcp" `
        -Method POST -Headers $headers -Body $body -SkipHttpErrorAction
    Write-Host "Request $_`: $($response.StatusCode)"
}
```

**How to verify:**
- Requests 1–60: HTTP 200
- Requests 61–65: HTTP 429
- Wait 60 seconds, send another request — should return 200 (counter reset)

---

## Scenario 3: Method-based differentiation

**What:** Alternate between `tools/call` and `tools/list` requests. Verify each method has its own independent rate limit counter.

**Expected:** Hitting the `tools/call` limit (10/min) does not affect `tools/list` requests, and vice versa.

**Command (curl):**

```bash
SESSION="test-session-003"

# Send 10 tools/call (should all pass)
echo "=== Sending 10 tools/call ==="
for i in $(seq 1 10); do
  echo -n "tools/call $i: "
  curl -s -o /dev/null -w "%{http_code}" \
    -X POST "https://aigw-apim-b5gl.azure-api.net/learn/mcp" \
    -H "Content-Type: application/json" \
    -H "api-key: $API_KEY" \
    -H "Mcp-Session-Id: $SESSION" \
    -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"search","arguments":{"query":"test"}},"id":1}'
  echo
done

# 11th tools/call should be 429
echo "=== 11th tools/call (expect 429) ==="
curl -s -o /dev/null -w "%{http_code}" \
  -X POST "https://aigw-apim-b5gl.azure-api.net/learn/mcp" \
  -H "Content-Type: application/json" \
  -H "api-key: $API_KEY" \
  -H "Mcp-Session-Id: $SESSION" \
  -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"search","arguments":{"query":"test"}},"id":1}'
echo

# tools/list should still work (different counter)
echo "=== tools/list (expect 200) ==="
curl -s -o /dev/null -w "%{http_code}" \
  -X POST "https://aigw-apim-b5gl.azure-api.net/learn/mcp" \
  -H "Content-Type: application/json" \
  -H "api-key: $API_KEY" \
  -H "Mcp-Session-Id: $SESSION" \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":1}'
echo
```

**How to verify:**
- `tools/call` requests 1–10: HTTP 200
- `tools/call` request 11: HTTP 429
- `tools/list` request after: HTTP 200 (independent counter, not exhausted)

---

## Scenario 4: Session isolation

**What:** Two different `Mcp-Session-Id` values each have their own independent rate limit counters.

**Expected:** Exhausting the limit on session A does not affect session B.

**Command (curl):**

```bash
# Exhaust tools/call limit on session-A
echo "=== Session A: exhaust tools/call limit ==="
for i in $(seq 1 11); do
  echo -n "Session-A request $i: "
  curl -s -o /dev/null -w "%{http_code}" \
    -X POST "https://aigw-apim-b5gl.azure-api.net/learn/mcp" \
    -H "Content-Type: application/json" \
    -H "api-key: $API_KEY" \
    -H "Mcp-Session-Id: session-A" \
    -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"search","arguments":{"query":"test"}},"id":1}'
  echo
done

# Session B should still work
echo "=== Session B: should still work ==="
for i in $(seq 1 3); do
  echo -n "Session-B request $i: "
  curl -s -o /dev/null -w "%{http_code}" \
    -X POST "https://aigw-apim-b5gl.azure-api.net/learn/mcp" \
    -H "Content-Type: application/json" \
    -H "api-key: $API_KEY" \
    -H "Mcp-Session-Id: session-B" \
    -d '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"search","arguments":{"query":"test"}},"id":1}'
  echo
done
```

**How to verify:**
- Session A requests 1–10: HTTP 200, request 11: HTTP 429
- Session B requests 1–3: all HTTP 200 (separate counter)

---

## Scenario 5: Correlation ID tracing

**What:** Make any MCP request and verify the `X-Correlation-Id` header appears in the response. Use the ID to look up the request in APIM logs.

**Expected:** Response includes `X-Correlation-Id` header. The same ID appears in Log Analytics.

**Command (curl):**

```bash
curl -v -X POST "https://aigw-apim-b5gl.azure-api.net/learn/mcp" \
  -H "Content-Type: application/json" \
  -H "api-key: $API_KEY" \
  -H "Mcp-Session-Id: test-session-005" \
  -d '{"jsonrpc":"2.0","method":"tools/list","id":1}' 2>&1 | grep -i "x-correlation-id"
```

**Command (PowerShell):**

```powershell
$response = Invoke-WebRequest -Uri "https://aigw-apim-b5gl.azure-api.net/learn/mcp" `
    -Method POST `
    -Headers @{
        "Content-Type" = "application/json"
        "api-key" = "$API_KEY"
        "Mcp-Session-Id" = "test-session-005"
    } `
    -Body '{"jsonrpc":"2.0","method":"tools/list","id":1}'

$correlationId = $response.Headers["X-Correlation-Id"]
Write-Host "Correlation ID: $correlationId"
```

**How to verify:**

1. Copy the `X-Correlation-Id` value from the response headers
2. In Azure portal → APIM → **Monitoring** → **Logs**
3. Run this KQL query:

```kql
ApiManagementGatewayLogs
| where CorrelationId == "<your-correlation-id>"
| project TimeGenerated, OperationId, ApiId, ResponseCode, DurationMs
```

4. The query should return a row matching your request with the correct API name, response code, and timing
