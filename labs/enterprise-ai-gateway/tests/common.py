"""Shared client factory and constants for AI Gateway v2 tests.

All tests use the standard OpenAI SDK (not AzureOpenAI). The gateway URL
points to APIM's unified v1 path: https://NAME.azure-api.net/openai/v1
The SDK auto-appends /chat/completions.
"""
import os
import sys

MODEL = "gpt-51"

REQUIRED_VARS = [
    "AIGW_GATEWAY_URL",
    "AIGW_ALPHA_KEY",
    "AIGW_BETA_KEY",
    "AIGW_GAMMA_KEY",
]


def check_env(extra_vars: list[str] | None = None):
    """Validate that required environment variables are set. Exits on failure."""
    missing = []
    for var in REQUIRED_VARS + (extra_vars or []):
        if not os.environ.get(var):
            missing.append(var)
    if missing:
        print(f"ERROR: Missing environment variables: {', '.join(missing)}")
        print("Run set_env.ps1 first:  . .\\set_env.ps1")
        sys.exit(1)


def make_client(key_var: str = "AIGW_ALPHA_KEY"):
    """Create an OpenAI client configured for the APIM gateway.

    The subscription key is sent as both the Authorization Bearer token
    (via api_key) and the api-key header (via default_headers) so APIM
    can authenticate regardless of its subscription-key header config.
    """
    from openai import OpenAI

    key = os.environ[key_var]
    return OpenAI(
        base_url=os.environ["AIGW_GATEWAY_URL"],
        api_key=key,
        default_headers={"api-key": key},
    )
