"""Test 2: Model Router — verify it resolves to an underlying model."""
from common import check_env, make_client

check_env()
client = make_client("AIGW_ALPHA_KEY")

r = client.chat.completions.create(
    model="model-router",
    messages=[{"role": "user", "content": "What is 2+2?"}],
    max_completion_tokens=10,
)
print(f"Router selected: {r.model}")
print(f"Response: {r.choices[0].message.content}")
