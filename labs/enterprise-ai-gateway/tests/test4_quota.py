"""Test 4: Quota enforcement — Gamma (500 TPM) should hit 429 via llm-token-limit.

Sends requests with large max_completion_tokens to burn through Gamma's
token budget quickly. Expects a 429 within ~10 requests.

Uses max_retries=0 so the SDK doesn't silently retry on 429 (default is 2 retries
with backoff, which can push past the TPM window reset).
"""
import sys
from openai import RateLimitError
from common import check_env, make_client, MODEL

check_env()
client = make_client("AIGW_GAMMA_KEY")
client = client.with_options(max_retries=0)

got_429 = False
for i in range(20):
    try:
        r = client.chat.completions.create(
            model=MODEL,
            messages=[{"role": "user", "content": f"Write 100 words about topic {i}"}],
            max_completion_tokens=200,
        )
        print(f"[{i+1}] OK - {r.usage.total_tokens} tokens")
    except RateLimitError as e:
        print(f"[{i+1}] 429 - quota enforced!")
        got_429 = True
        break
    except Exception as e:
        print(f"[{i+1}] {type(e).__name__}: {e}")
        break

if not got_429:
    print("WARN: never hit 429 — Gamma quota may be too high or not configured")
    sys.exit(1)
