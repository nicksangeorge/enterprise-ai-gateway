"""Debug: print env vars and test raw HTTP connectivity (no SDK dependency).

Use this to isolate whether the problem is the SDK or the gateway itself.
Expects AIGW_GATEWAY_URL to be the full v1 path:
    https://NAME.azure-api.net/openai/v1
"""
import os
import sys
import urllib.request
import json

gw = os.environ.get("AIGW_GATEWAY_URL", "NOT SET")
alpha = os.environ.get("AIGW_ALPHA_KEY", "NOT SET")
beta = os.environ.get("AIGW_BETA_KEY", "NOT SET")
gamma = os.environ.get("AIGW_GAMMA_KEY", "NOT SET")
rg = os.environ.get("AIGW_RESOURCE_GROUP", "NOT SET")
foundry = os.environ.get("AIGW_FOUNDRY_EUS2", "NOT SET")

print("=== Environment Variables ===")
print(f"  AIGW_GATEWAY_URL    = {gw}")
print(f"  AIGW_ALPHA_KEY      = {alpha[:8]}..." if len(alpha) > 8 else f"  AIGW_ALPHA_KEY      = {alpha}")
print(f"  AIGW_BETA_KEY       = {beta[:8]}..." if len(beta) > 8 else f"  AIGW_BETA_KEY       = {beta}")
print(f"  AIGW_GAMMA_KEY      = {gamma[:8]}..." if len(gamma) > 8 else f"  AIGW_GAMMA_KEY      = {gamma}")
print(f"  AIGW_RESOURCE_GROUP = {rg}")
print(f"  AIGW_FOUNDRY_EUS2   = {foundry}")
print()

if gw == "NOT SET" or alpha == "NOT SET":
    print("ERROR: Required environment variables not set!")
    print("Run:  . .\\set_env.ps1")
    sys.exit(1)

# Raw HTTP test — no SDK involved
url = f"{gw}/chat/completions"
body = json.dumps({
    "model": "gpt-51",
    "messages": [{"role": "user", "content": "Say hello"}],
    "max_completion_tokens": 10,
}).encode()
req = urllib.request.Request(url, data=body, headers={
    "api-key": alpha,
    "Content-Type": "application/json",
})

print(f"=== Raw HTTP Test ===")
print(f"  URL: {url}")
try:
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read())
        print(f"  Status: {resp.status}")
        print(f"  Model:  {data['model']}")
        print(f"  Reply:  {data['choices'][0]['message']['content']}")
        print(f"  Tokens: {data['usage']['total_tokens']}")
except urllib.error.HTTPError as e:
    body = e.read().decode()[:300]
    print(f"  HTTP {e.code}: {body}")
    sys.exit(1)
