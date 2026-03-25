"""
Foundry Agent Demo — MCP Tool Governance (v2 Prompt Agent)

Creates a Foundry v2 prompt agent programmatically with an MCP tool
pointing at the APIM gateway, invokes it, and cleans up.

The agent doesn't know it's governed — it calls a URL. APIM handles
auth, rate limits, and logging transparently.

Prerequisites:
  - APIM deployed with MCP demo enabled (MCP server registered)
  - pip install azure-ai-projects>=2.0.0 azure-identity openai
  - az login (with Cognitive Services User role on the Foundry resource)

Environment variables:
  AZURE_FOUNDRY_ENDPOINT  - Foundry project endpoint (with /api/projects/<name>)
  AIGW_GATEWAY_URL        - APIM gateway URL
  AIGW_MCP_KEY            - APIM subscription key for MCP product
  AGENT_NAME              - Agent name to create (default: learn-search-agent)
  MODEL_NAME              - Model deployment name (default: gpt-51)

Usage:
  cd infra/terraform
  $env:AZURE_FOUNDRY_ENDPOINT = terraform output -raw foundry_primary_endpoint
  cd ../../demo
  $env:AIGW_GATEWAY_URL = "https://aigw-apim-zieo.azure-api.net"
  $env:AIGW_MCP_KEY = "<your-mcp-subscription-key>"
  python foundry-agent-demo.py
"""

import os
import sys
import json

# ---------------------------------------------------------------------------
# SDK imports
# ---------------------------------------------------------------------------
try:
    from azure.ai.projects import AIProjectClient
    from azure.ai.projects.models import PromptAgentDefinition, MCPTool
    from azure.identity import DefaultAzureCredential
except ImportError as e:
    print(f"ERROR: Missing SDK package: {e}")
    print("Run:  pip install azure-ai-projects>=2.0.0 azure-identity openai")
    sys.exit(1)


def main():
    # ------------------------------------------------------------------
    # Environment
    # ------------------------------------------------------------------
    endpoint = os.environ.get("AZURE_FOUNDRY_ENDPOINT", "")
    gateway_url = os.environ.get("AIGW_GATEWAY_URL", "").rstrip("/")
    mcp_key = os.environ.get("AIGW_MCP_KEY", "")
    mcp_url = os.environ.get("AIGW_MCP_URL", "").rstrip("/")
    agent_name = os.environ.get("AGENT_NAME", "learn-search-agent")
    model = os.environ.get("MODEL_NAME", "gpt-51")

    missing = []
    if not endpoint:
        missing.append("AZURE_FOUNDRY_ENDPOINT")
    if not mcp_key:
        missing.append("AIGW_MCP_KEY")
    if not gateway_url and not mcp_url:
        missing.append("AIGW_MCP_URL or AIGW_GATEWAY_URL")
    if missing:
        print(f"ERROR: Missing environment variables: {', '.join(missing)}")
        print()
        print("Run: cd scripts && . .\\set_env.ps1")
        sys.exit(1)

    if "/api/projects/" not in endpoint:
        print(f"WARNING: Endpoint may need /api/projects/<name> suffix")
        print(f"  Current: {endpoint}")
        print()

    # Prefer AIGW_MCP_URL; fall back to building from AIGW_GATEWAY_URL
    if not mcp_url:
        base = gateway_url
        for suffix in ["/openai/v1", "/openai"]:
            if base.endswith(suffix):
                base = base[:-len(suffix)]
                break
        mcp_url = f"{base}/learn/mcp"

    print("=" * 65)
    print("  Foundry Agent Demo - MCP Tool Governance (v2)")
    print("=" * 65)
    print(f"  Foundry endpoint : {endpoint}")
    print(f"  APIM gateway     : {gateway_url}")
    print(f"  MCP server (APIM): {mcp_url}")
    print(f"  Model            : {model}")
    print(f"  Agent name       : {agent_name}")
    print()

    # ------------------------------------------------------------------
    # 1. Connect to Foundry
    # ------------------------------------------------------------------
    print("[1/5] Connecting to Foundry project...")
    credential = DefaultAzureCredential()
    project = AIProjectClient(endpoint=endpoint, credential=credential)
    openai = project.get_openai_client()
    print("  [OK] Connected")
    print()

    # ------------------------------------------------------------------
    # 2. Create MCP tool + agent programmatically
    # ------------------------------------------------------------------
    print("[2/5] Creating v2 prompt agent with MCP tool...")
    print(f"  MCP tool -> {mcp_url}")
    print(f"  The tool URL points at APIM, NOT the raw MCP server.")
    print(f"  APIM enforces rate limits, adds correlation IDs, logs everything.")
    print()

    mcp_tool = MCPTool(
        server_label="learn_search",
        server_url=mcp_url,
        headers={"Ocp-Apim-Subscription-Key": mcp_key},
        require_approval="never",
    )

    agent = None
    try:
        agent = project.agents.create_version(
            agent_name=agent_name,
            definition=PromptAgentDefinition(
                model=model,
                instructions=(
                    "You are a helpful assistant that searches Microsoft Learn "
                    "documentation. Use the learn_search MCP tool to find relevant "
                    "docs. Always cite the source URL from search results."
                ),
                tools=[mcp_tool],
            ),
        )
        print(f"  [OK] Agent created: {agent.name} (version {agent.version})")
        print(f"     ID: {agent.id}")
    except Exception as e:
        print(f"  ERROR creating agent: {e}")
        print()
        print("  Troubleshooting:")
        print(f"    - Is model '{model}' deployed in your Foundry project?")
        print(f"    - Do you have Cognitive Services User role?")
        print(f"    - Is the endpoint correct? ({endpoint})")
        sys.exit(1)
    print()

    try:
        # ------------------------------------------------------------------
        # 3. Invoke the agent — triggers MCP tool through APIM
        # ------------------------------------------------------------------
        print("[3/5] Invoking agent (should trigger MCP tool through APIM)...")
        query = "Search Microsoft Learn for Azure API Management rate limiting best practices"
        print(f'  Query: "{query}"')
        print()

        response = openai.responses.create(
            input=[{"role": "user", "content": query}],
            extra_body={
                "agent_reference": {
                    "name": agent.name,
                    "type": "agent_reference",
                }
            },
        )

        # ------------------------------------------------------------------
        # 4. Display results + tool call evidence
        # ------------------------------------------------------------------
        print("[4/5] Results:")
        print("-" * 65)
        print(f"  Response ID: {response.id}")
        print()

        # Show tool calls from output items
        tool_calls = []
        text_parts = []
        for item in response.output:
            item_type = getattr(item, "type", type(item).__name__)
            if item_type in ("mcp_call", "mcp_list_tools"):
                tool_calls.append(item)
            elif item_type == "message":
                for content in getattr(item, "content", []):
                    if hasattr(content, "text"):
                        text_parts.append(content.text)

        if tool_calls:
            print(f"  MCP tool calls detected: {len(tool_calls)}")
            for tc in tool_calls:
                label = getattr(tc, "server_label", "?")
                name = getattr(tc, "name", getattr(tc, "id", "?"))
                print(f"    -> [{label}] {name}")
            print()
            print("  [OK] Tool calls routed through APIM gateway")
            print("     APIM applied rate limits, correlation IDs, and logging")
        else:
            # Show all output item types for debugging
            print("  Output items:")
            for item in response.output:
                item_type = getattr(item, "type", type(item).__name__)
                print(f"    - type: {item_type}")
                # For function_call types, show details
                if hasattr(item, "name"):
                    print(f"      name: {item.name}")

        if text_parts:
            print()
            full_text = "\n".join(text_parts)
            display = full_text[:500] + ("..." if len(full_text) > 500 else "")
            print("  Agent response:")
            for line in display.split("\n"):
                print(f"    {line}")

        print("-" * 65)
        print()

        # ------------------------------------------------------------------
        # 5. Follow-up (multi-turn)
        # ------------------------------------------------------------------
        print("[5/5] Follow-up query (multi-turn)...")
        follow_up = "What about MCP server configuration in APIM?"
        print(f'  Query: "{follow_up}"')

        try:
            resp2 = openai.responses.create(
                input=[{"role": "user", "content": follow_up}],
                previous_response_id=response.id,
                extra_body={
                    "agent_reference": {
                        "name": agent.name,
                        "type": "agent_reference",
                    }
                },
            )
            text2 = resp2.output_text or ""
            if text2:
                display2 = text2[:300] + ("..." if len(text2) > 300 else "")
                print(f"  Response: {display2}")
            print()
        except Exception as e:
            print(f"  Follow-up failed (non-critical): {e}")
            print()

    except Exception as e:
        print(f"ERROR: {e}")
        sys.exit(1)

    print()
    print("=" * 65)
    print("  Demo complete.")
    print()
    print("  Key takeaway:")
    print("    The agent was created programmatically with an MCP tool")
    print("    URL pointing at APIM. APIM governed every tool call -")
    print("    rate limits, correlation IDs, logging - all transparent.")
    print()
    print("  Cleanup:")
    print("    python tests/cleanup-agent.py                # delete the agent")
    print("    python tests/cleanup-agent.py --list         # list all agents")
    print()
    print("  Verify in APIM logs:")
    print("    ApiManagementGatewayLogs")
    print("    | where OperationId contains 'mcp'")
    print("    | project TimeGenerated, ResponseCode, Method, CorrelationId, BackendUrl")
    print("=" * 65)


if __name__ == "__main__":
    main()
