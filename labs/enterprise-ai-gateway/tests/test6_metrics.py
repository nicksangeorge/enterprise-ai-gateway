"""Test 6: Token metrics in App Insights — send a request then print KQL.

The llm-emit-token-metric policy emits token counts to App Insights
customMetrics. This test sends one request to generate data, then
prints the KQL query to verify in the portal.
"""
from common import check_env, make_client, MODEL

check_env()
client = make_client("AIGW_ALPHA_KEY")

print("Sending a request to generate token metrics...")
r = client.chat.completions.create(
    model=MODEL,
    messages=[{"role": "user", "content": "Say hello in one sentence."}],
    max_completion_tokens=20,
)
print(f"OK: {r.model} | {r.usage.total_tokens} tokens")
print()
print("Wait 3-5 minutes, then run this KQL in App Insights (not Log Analytics):")
print("  Azure portal > your App Insights resource > Logs")
print()
print("  customMetrics")
print("  | where timestamp > ago(30m)")
print('  | where name == "Total Tokens" or name == "Prompt Tokens" or name == "Completion Tokens"')
print("  | summarize Sum=sum(valueSum) by name, bin(timestamp, 1m)")
print("  | order by timestamp desc")
print()
print("Expected: rows with Total Tokens, Prompt Tokens, and Completion Tokens.")
