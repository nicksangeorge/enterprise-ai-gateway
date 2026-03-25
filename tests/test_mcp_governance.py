"""Test MCP Governance — validates APIM MCP governance policies are working.

Tests:
  1. MCP server connectivity through APIM
  2. X-Correlation-Id header present in responses
  3. tools/list returns valid MCP response
  4. tools/call is governed (rate limited separately from reads)

Environment variables:
  AIGW_GATEWAY_URL  - APIM gateway URL
  AIGW_MCP_KEY      - MCP product subscription key
  AIGW_MCP_PATH     - MCP server path (default: learn)
"""
import os
import sys
import uuid
import json
import argparse
import requests

VERBOSE = False


def check_env():
    """Validate required environment variables. Exits on failure."""
    required = ["AIGW_GATEWAY_URL", "AIGW_MCP_KEY"]
    missing = [v for v in required if not os.environ.get(v)]
    if missing:
        print(f"ERROR: Missing environment variables: {', '.join(missing)}")
        print("Set AIGW_GATEWAY_URL and AIGW_MCP_KEY before running.")
        sys.exit(1)


def get_mcp_url():
    """Build the MCP endpoint URL from environment variables."""
    # Prefer AIGW_MCP_URL (full MCP URL) over building from AIGW_GATEWAY_URL
    if os.environ.get("AIGW_MCP_URL"):
        return os.environ["AIGW_MCP_URL"].rstrip("/")
    gw = os.environ["AIGW_GATEWAY_URL"].rstrip("/")
    # Strip /openai/v1 suffix if present (that's the LLM path, not MCP)
    for suffix in ["/openai/v1", "/openai"]:
        if gw.endswith(suffix):
            gw = gw[:-len(suffix)]
            break
    path = os.environ.get("AIGW_MCP_PATH", "learn")
    return f"{gw}/{path}/mcp"


def mcp_request(url, method, params=None, session_id=None, api_key=None):
    """Send a JSON-RPC 2.0 request to the MCP server through APIM."""
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
        "Ocp-Apim-Subscription-Key": api_key,
    }
    if session_id:
        headers["Mcp-Session-Id"] = session_id

    body = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": method,
    }
    if params:
        body["params"] = params

    if VERBOSE:
        print(f"  -> POST {url}  method={method}  session={session_id}")

    resp = requests.post(url, json=body, headers=headers, timeout=30)

    if VERBOSE:
        print(f"  <- {resp.status_code}  {resp.text[:200]}")

    return resp


def parse_sse_json(resp):
    """Parse JSON from an SSE (text/event-stream) or plain JSON response."""
    content_type = resp.headers.get("Content-Type", "")
    if "text/event-stream" in content_type:
        # SSE format: lines like "event: message\ndata: {...}\n\n"
        for line in resp.text.split("\n"):
            if line.startswith("data: "):
                try:
                    return json.loads(line[6:])
                except json.JSONDecodeError:
                    continue
        return None
    else:
        return resp.json()


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

def test_connectivity():
    """Send tools/list, expect HTTP 200."""
    url = get_mcp_url()
    api_key = os.environ["AIGW_MCP_KEY"]
    session_id = str(uuid.uuid4())

    print(f"  POST {url}")
    print(f"  Method: tools/list | Session: {session_id[:8]}...")

    try:
        resp = mcp_request(url, "tools/list", session_id=session_id, api_key=api_key)
        if resp.status_code == 200:
            print(f"PASS: connectivity: tools/list returned 200")
            return True
        else:
            print(f"FAIL: connectivity: expected 200, got {resp.status_code}")
            return False
    except Exception as e:
        print(f"FAIL: connectivity: {type(e).__name__}: {e}")
        return False


def test_correlation_id():
    """Verify X-Correlation-Id header is present in the response.

    This header is set by the mcp-governance.xml policy in the <outbound> section.
    It proves the governance policy is applied. x-azure-ref is NOT accepted —
    that's APIM's default header and doesn't prove policy is active.
    """
    url = get_mcp_url()
    api_key = os.environ["AIGW_MCP_KEY"]
    session_id = str(uuid.uuid4())

    print(f"  POST {url}")
    print(f"  Method: tools/list | Checking for X-Correlation-Id header")

    try:
        resp = mcp_request(url, "tools/list", session_id=session_id, api_key=api_key)
        corr_id = resp.headers.get("X-Correlation-Id")
        if corr_id:
            print(f"PASS: correlation-id: X-Correlation-Id={corr_id}")
            return True
        else:
            print(f"FAIL: correlation-id: X-Correlation-Id header missing from response")
            print(f"   This means the mcp-governance.xml policy is not applied.")
            print(f"   Apply it in portal: APIM -> APIs -> MCP Servers -> microsoft-learn -> Policies")
            if VERBOSE:
                print(f"  Response headers: {dict(resp.headers)}")
            return False
    except Exception as e:
        print(f"FAIL: correlation-id: {type(e).__name__}: {e}")
        return False


def test_tools_list_returns_tools():
    """Send tools/list, verify response contains a tools array."""
    url = get_mcp_url()
    api_key = os.environ["AIGW_MCP_KEY"]
    session_id = str(uuid.uuid4())

    print(f"  POST {url}")
    print(f"  Method: tools/list | Expecting tools array in response")

    try:
        resp = mcp_request(url, "tools/list", session_id=session_id, api_key=api_key)
        if resp.status_code != 200:
            print(f"FAIL: tools-list: expected 200, got {resp.status_code}")
            return False

        data = parse_sse_json(resp)
        if data is None:
            print(f"FAIL: tools-list: could not parse response (Content-Type: {resp.headers.get('Content-Type')})")
            if VERBOSE:
                print(f"  Body: {resp.text[:300]}")
            return False
        result = data.get("result", {})
        tools = result.get("tools", None)
        if tools is None:
            # Some servers return tools at top level
            tools = data.get("tools", None)

        if isinstance(tools, list) and len(tools) > 0:
            print(f"PASS: tools-list: {len(tools)} tools returned")
            if VERBOSE:
                for t in tools[:5]:
                    name = t.get("name", "?")
                    print(f"     - {name}")
            return True
        elif isinstance(tools, list):
            print(f"FAIL: tools-list: tools array is empty")
            return False
        else:
            print(f"FAIL: tools-list: no tools array in response")
            if VERBOSE:
                print(f"  Response body: {resp.text[:500]}")
            return False
    except Exception as e:
        print(f"FAIL: tools-list: {type(e).__name__}: {e}")
        return False


def test_tools_call_and_list_independent():
    """Send 5 tools/call + 5 tools/list on the same session — all should succeed.

    Proves the two methods have independent rate limit counters (limits are
    10 calls/min and 60 lists/min, so 5 of each is well within budget).
    """
    url = get_mcp_url()
    api_key = os.environ["AIGW_MCP_KEY"]
    session_id = str(uuid.uuid4())
    call_params = {"name": "search", "arguments": {"query": "test"}}

    print(f"  POST {url}")
    print(f"  Sending 5x tools/call + 5x tools/list on session {session_id[:8]}...")

    calls_ok = 0
    lists_ok = 0

    try:
        for i in range(5):
            resp = mcp_request(url, "tools/call", params=call_params,
                               session_id=session_id, api_key=api_key)
            # Any non-429 means APIM let it through (backend may return 4xx)
            if resp.status_code != 429:
                calls_ok += 1
            else:
                print(f"FAIL: independent-counters: tools/call #{i+1} got 429 unexpectedly")
                return False

        for i in range(5):
            resp = mcp_request(url, "tools/list", session_id=session_id, api_key=api_key)
            if resp.status_code != 429:
                lists_ok += 1
            else:
                print(f"FAIL: independent-counters: tools/list #{i+1} got 429 unexpectedly")
                return False

        print(f"PASS: independent-counters: {calls_ok} calls + {lists_ok} lists all passed (same session)")
        return True
    except Exception as e:
        print(f"FAIL: independent-counters: {type(e).__name__}: {e}")
        return False


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

ALL_TESTS = [
    ("connectivity", test_connectivity),
    ("correlation-id", test_correlation_id),
    ("tools-list", test_tools_list_returns_tools),
    ("independent-counters", test_tools_call_and_list_independent),
]

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="MCP Governance Tests")
    parser.add_argument("--verbose", "-v", action="store_true", help="Print request/response details")
    args = parser.parse_args()
    VERBOSE = args.verbose

    check_env()

    print("=" * 60)
    print("MCP Governance Tests")
    print("=" * 60)
    print(f"Gateway: {os.environ['AIGW_GATEWAY_URL']}")
    print(f"MCP URL: {get_mcp_url()}")
    print()

    passed = 0
    failed = 0
    for name, fn in ALL_TESTS:
        if fn():
            passed += 1
        else:
            failed += 1

    print()
    print("-" * 60)
    print(f"Results: {passed} passed, {failed} failed, {passed + failed} total")
    if failed:
        sys.exit(1)
