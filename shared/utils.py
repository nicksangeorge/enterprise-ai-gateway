"""
Minimal shared utilities for local testing.

When this lab is contributed to Azure-Samples/AI-Gateway, the full shared/utils.py
from that repo is used instead. This shim provides just enough for the notebook
to run standalone.
"""
import datetime, json, os, subprocess, time


class Output:
    def __init__(self, success, text):
        self.success = success
        self.text = text
        try:
            self.json_data = json.loads(text)
        except (json.JSONDecodeError, TypeError):
            self.json_data = {}


def run(command, ok_message='', error_message='', print_output=False, print_command_to_run=True):
    if print_command_to_run:
        print(f"\033[90m$ {command}\033[0m")
    try:
        result = subprocess.run(command, shell=True, capture_output=True, text=True, timeout=600)
        output_text = result.stdout.strip()
        if result.returncode == 0:
            if ok_message:
                print_ok(ok_message)
            if print_output and output_text:
                print(output_text)
            return Output(True, output_text)
        else:
            err = result.stderr.strip() or output_text
            if error_message:
                print_error(f"{error_message}: {err}")
            return Output(False, err)
    except subprocess.TimeoutExpired:
        print_error(f"Command timed out: {command}")
        return Output(False, "timeout")


def print_ok(message, output='', duration=''):
    print(f"\033[92m  ✓ {message}\033[0m")

def print_error(message, output='', duration=''):
    print(f"\033[91m  ✗ {message}\033[0m")

def print_info(message):
    print(f"\033[94m  → {message}\033[0m")

def print_warning(message, output='', duration=''):
    print(f"\033[93m  ⚠ {message}\033[0m")

def print_message(message, output='', duration=''):
    print(f"\033[92m  {message}\033[0m")


def get_current_subscription():
    output = run("az account show", print_command_to_run=False)
    if output.success and output.json_data:
        return output.json_data.get('id')
    return None


def create_resource_group(resource_group_name, resource_group_location=None):
    loc = f" -l {resource_group_location}" if resource_group_location else ""
    run(f"az group create -n {resource_group_name}{loc} -o none",
        f"Resource group '{resource_group_name}' ready",
        f"Failed to create resource group '{resource_group_name}'")


def cleanup_resources(deployment_name, resource_group_name=None):
    rg = resource_group_name or f"lab-{deployment_name}"
    print_info(f"Deleting resource group: {rg}")
    run(f"az group delete -n {rg} -y --no-wait",
        f"Resource group '{rg}' deletion initiated",
        f"Failed to delete resource group '{rg}'")


def update_api_policy(subscription_id, resource_group_name, apim_service_name, api_id, policy_xml):
    import tempfile
    body = json.dumps({"properties": {"format": "xml", "value": policy_xml}})
    with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False, encoding='utf-8') as f:
        f.write(body)
        tmp = f.name
    try:
        uri = (f"https://management.azure.com/subscriptions/{subscription_id}"
               f"/resourceGroups/{resource_group_name}"
               f"/providers/Microsoft.ApiManagement/service/{apim_service_name}"
               f"/apis/{api_id}/policies/policy?api-version=2024-05-01")
        run(f'az rest --method PUT --url "{uri}" --body @{tmp}',
            "API policy updated", "Failed to update API policy")
    finally:
        os.unlink(tmp)


def get_deployment_output(output, output_property, output_label='', secure=False):
    if output.success and output.json_data:
        props = output.json_data.get('properties', {}).get('outputs', {})
        val = props.get(output_property, {}).get('value', '')
        if output_label and not secure:
            print_ok(f"{output_label}: {val}")
        return val
    return ''
