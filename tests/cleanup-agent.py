"""
Cleanup Foundry Agent — delete agent versions created by the demo.

Usage:
  python demo/cleanup-agent.py                          # delete learn-search-agent v1
  python demo/cleanup-agent.py --name my-agent          # delete specific agent (all versions)
  python demo/cleanup-agent.py --name my-agent --version 3  # delete specific version
  python demo/cleanup-agent.py --list                   # list all agents in the project
"""

import argparse
import os
import sys

try:
    from azure.ai.projects import AIProjectClient
    from azure.identity import DefaultAzureCredential
except ImportError:
    print("ERROR: pip install azure-ai-projects>=2.0.0 azure-identity")
    sys.exit(1)


def get_client():
    endpoint = os.environ.get("AZURE_FOUNDRY_ENDPOINT", "")
    if not endpoint:
        print("ERROR: AZURE_FOUNDRY_ENDPOINT not set.")
        print('  $env:AZURE_FOUNDRY_ENDPOINT = "https://<account>.services.ai.azure.com/api/projects/<project>"')
        sys.exit(1)
    return AIProjectClient(endpoint=endpoint, credential=DefaultAzureCredential())


def list_agents(client):
    print("Agents in project:")
    print("-" * 50)
    found = False
    for agent in client.agents.list():
        found = True
        name = agent.name
        print(f"  {name}")
        for ver in client.agents.list_versions(agent_name=name):
            version = ver.version
            model = getattr(ver.definition, "model", "?") if ver.definition else "?"
            print(f"    v{version}  (model: {model})")
    if not found:
        print("  (none)")


def delete_agent(client, name, version=None):
    if version:
        print(f"Deleting {name} v{version}...")
        client.agents.delete_version(agent_name=name, agent_version=version)
        print(f"  [OK] Deleted {name} v{version}")
    else:
        print(f"Deleting all versions of {name}...")
        versions = list(client.agents.list_versions(agent_name=name))
        if not versions:
            print(f"  No versions found for {name}")
            return
        for ver in versions:
            v = ver.version
            client.agents.delete_version(agent_name=name, agent_version=v)
            print(f"  [OK] Deleted {name} v{v}")


def main():
    parser = argparse.ArgumentParser(description="Cleanup Foundry agents")
    parser.add_argument("--name", default="learn-search-agent", help="Agent name (default: learn-search-agent)")
    parser.add_argument("--version", default=None, help="Specific version to delete (default: all versions)")
    parser.add_argument("--list", action="store_true", help="List all agents instead of deleting")
    args = parser.parse_args()

    client = get_client()

    if args.list:
        list_agents(client)
    else:
        try:
            delete_agent(client, args.name, args.version)
        except Exception as e:
            print(f"  ERROR: {e}")
            sys.exit(1)


if __name__ == "__main__":
    main()
