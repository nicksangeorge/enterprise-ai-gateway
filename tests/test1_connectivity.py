"""Test 1: Basic connectivity — send a request as Team Alpha through the gateway.

Uses the standard OpenAI SDK against the APIM unified v1 path.
APIM authenticates to the Foundry backend via managed identity.
"""
from common import check_env, make_client, MODEL

check_env()
client = make_client("AIGW_ALPHA_KEY")

r = client.chat.completions.create(
    model=MODEL,
    messages=[{"role": "user", "content": "Say hello in one sentence."}],
    max_completion_tokens=20,
)
print(f"OK: {r.model}")
print(f"Response: {r.choices[0].message.content}")
print(f"Tokens: {r.usage.total_tokens}")
