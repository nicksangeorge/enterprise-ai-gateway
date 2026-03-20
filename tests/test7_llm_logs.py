"""Test 7: LLM logs in Log Analytics — send a request then print KQL.

The azuremonitor diagnostic with largeLanguageModel.logs enabled pipes
data to the ApiManagementGatewayLlmLog table (singular, not plural)
in the Log Analytics workspace. This test sends one request to generate
log data, then prints the KQL query to verify.
"""
from common import check_env, make_client, MODEL

check_env()
client = make_client("AIGW_ALPHA_KEY")

print("Sending a request to generate LLM log data...")
r = client.chat.completions.create(
    model=MODEL,
    messages=[{"role": "user", "content": "Say hello in one sentence."}],
    max_completion_tokens=20,
)
print(f"OK: {r.model} | {r.usage.total_tokens} tokens")
print()
print("Wait 3-5 minutes, then run this KQL in the Log Analytics workspace:")
print("  Azure portal > your Log Analytics workspace > Logs")
print()
print("  ApiManagementGatewayLlmLog")
print("  | where TimeGenerated > ago(30m)")
print("  | project TimeGenerated, OperationName, BackendId, TotalTokens, PromptTokens, CompletionTokens")
print("  | order by TimeGenerated desc")
print("  | take 20")
print()
print("Expected: rows with token counts for recent requests.")
print("Note: table is ApiManagementGatewayLlmLog (singular), not plural.")
