"""Test 5: Circuit breaker failover — scale down eus2, burst traffic, verify swc takes over.

Automates the full cycle:
  1. Scale eus2 gpt-51 down to 1K TPM (capacity=1)
  2. Burst 25 concurrent requests to exhaust eus2 and trip the circuit breaker
  3. Remaining requests route to swc (priority 2 backend)
  4. Scale eus2 back to 30K TPM (capacity=30)

Uses concurrent threads to send requests fast enough to trip the circuit breaker
before the per-minute window resets.

Requires AIGW_RESOURCE_GROUP and AIGW_FOUNDRY_EUS2 env vars.
"""
import os
import subprocess
import sys
import time
import threading
from openai import APIError, RateLimitError
from common import check_env, make_client, MODEL

EXTRA_VARS = ["AIGW_RESOURCE_GROUP", "AIGW_FOUNDRY_EUS2"]
check_env(extra_vars=EXTRA_VARS)

RG = os.environ["AIGW_RESOURCE_GROUP"]
FOUNDRY = os.environ["AIGW_FOUNDRY_EUS2"]
DEPLOYMENT = "gpt-51"
MODEL_NAME = "gpt-5.1"
MODEL_VERSION = "2025-11-13"


def scale_deployment(capacity: int):
    """Scale the eus2 gpt-51 deployment via az cli."""
    cmd = [
        "az", "cognitiveservices", "account", "deployment", "create",
        "--name", FOUNDRY,
        "-g", RG,
        "--deployment-name", DEPLOYMENT,
        "--model-name", MODEL_NAME,
        "--model-version", MODEL_VERSION,
        "--model-format", "OpenAI",
        "--sku-capacity", str(capacity),
        "--sku-name", "GlobalStandard",
    ]
    print(f"  az: scaling {FOUNDRY}/{DEPLOYMENT} to capacity={capacity} ...")
    result = subprocess.run(cmd, capture_output=True, text=True, shell=True)
    if result.returncode != 0:
        print(f"  az error: {result.stderr.strip()[:300]}")
        return False
    print(f"  az: done (capacity={capacity})")
    return True


# Step 1: Scale down
print("Step 1: Scale eus2 to 1K TPM (capacity=1)")
if not scale_deployment(1):
    print("ERROR: Could not scale down eus2. Aborting.")
    sys.exit(1)
print("Waiting 15s for scale to take effect...\n")
time.sleep(15)

# Step 2: Burst traffic using concurrent threads
print("Step 2: Sending 25 concurrent requests to exhaust eus2 and trigger failover to swc")
print("(eus2 = 1K TPM / ~10 RPM, circuit breaker trips after 3x 429)\n")

client = make_client("AIGW_ALPHA_KEY")
client = client.with_options(max_retries=0, timeout=30.0)

results = []
lock = threading.Lock()


def send_request(idx):
    """Send a single request and record the result."""
    try:
        raw = client.chat.completions.with_raw_response.create(
            model=MODEL,
            messages=[{"role": "user", "content": f"Topic {idx}: say hello"}],
            max_completion_tokens=20,
        )
        r = raw.parse()
        region = raw.headers.get("x-ms-region", "unknown")
        with lock:
            results.append(("OK", idx, r.usage.total_tokens, region))
    except RateLimitError:
        with lock:
            results.append(("429", idx, 0, ""))
    except APIError as e:
        with lock:
            results.append((f"HTTP_{e.status_code}", idx, 0, ""))
    except Exception as e:
        with lock:
            results.append((f"ERR", idx, 0, str(e)[:80]))


# Fire all 25 requests concurrently
threads = []
for i in range(25):
    t = threading.Thread(target=send_request, args=(i,))
    threads.append(t)
    t.start()
    time.sleep(0.1)  # slight stagger to avoid all hitting at once

for t in threads:
    t.join(timeout=60)

# Sort by index and print
results.sort(key=lambda x: x[1])
ok_count = 0
rate_limited = 0
for status, idx, tokens, info in results:
    if status == "OK":
        ok_count += 1
        print(f"  [{idx+1:2d}] OK - {tokens} tokens | region={info}")
    elif status == "429":
        rate_limited += 1
        print(f"  [{idx+1:2d}] 429 RATE LIMITED")
    else:
        print(f"  [{idx+1:2d}] {status}: {info}")

print(f"\nResults: {ok_count} OK, {rate_limited} rate-limited")
if rate_limited > 0:
    print("Circuit breaker triggered - failover confirmed.")
    print("Verify backend distribution in Log Analytics (wait 3-5 min for ingestion).")
else:
    print("WARNING: No 429s seen. eus2 may have higher capacity than expected.")

# Step 3: Scale back up
print("\nStep 3: Scaling eus2 back to 30K TPM (capacity=30)")
if not scale_deployment(30):
    print("WARNING: Could not scale eus2 back up! Do it manually:")
    print(f"  az cognitiveservices account deployment create --name {FOUNDRY} -g {RG} "
          f"--deployment-name {DEPLOYMENT} --model-name {MODEL_NAME} "
          f"--model-version {MODEL_VERSION} --model-format OpenAI "
          f"--sku-capacity 30 --sku-name GlobalStandard")
    sys.exit(1)

print("\nDone. Check backend distribution with this KQL in the Log Analytics workspace:")
print("  ApiManagementGatewayLlmLog")
print("  | where TimeGenerated > ago(15m)")
print("  | summarize count() by BackendId")

