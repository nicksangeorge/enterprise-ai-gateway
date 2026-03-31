"""Test 3: Concurrent load — all three teams sending requests simultaneously."""
import threading
import time
from openai import APIError, RateLimitError
from common import check_env, make_client, MODEL

check_env()

teams = [
    ("Alpha", "AIGW_ALPHA_KEY"),
    ("Beta",  "AIGW_BETA_KEY"),
    ("Gamma", "AIGW_GAMMA_KEY"),
]

results = []

def run_team(name, key_var):
    client = make_client(key_var)
    for i in range(5):
        try:
            r = client.chat.completions.create(
                model=MODEL,
                messages=[{"role": "user", "content": f"Hello from {name}, request {i}"}],
                max_completion_tokens=10,
            )
            results.append(f"  [{name}] OK - {r.usage.total_tokens} tokens")
        except RateLimitError:
            results.append(f"  [{name}] 429 RATE LIMITED")
        except APIError as e:
            results.append(f"  [{name}] HTTP {e.status_code}")
        except Exception as e:
            results.append(f"  [{name}] {type(e).__name__}: {e}")
        time.sleep(1)

threads = [threading.Thread(target=run_team, args=(n, k)) for n, k in teams]
for t in threads:
    t.start()
for t in threads:
    t.join()

for line in sorted(results):
    print(line)
print(f"\nTotal requests: {len(results)}")

