import requests
import subprocess
import json

resource_group = "webserver"
nsg_name = "webserver-nsg"

rule_prefix = "CF-ALLOW-"
priority_start = 100
port = "443"

cf_ipv4 = requests.get("https://www.cloudflare.com/ips-v4").text.splitlines()
cf_ipv6 = requests.get("https://www.cloudflare.com/ips-v6").text.splitlines()
cf_ips = set(cf_ipv4 + cf_ipv6)

result = subprocess.run([
    "az", "network", "nsg", "rule", "list",
    "--resource-group", resource_group,
    "--nsg-name", nsg_name,
    "--output", "json"
], capture_output=True, text=True)

existing_rules = json.loads(result.stdout)

existing_cf_rules = {
    rule['name']: rule['sourceAddressPrefix']
    for rule in existing_rules
    if rule['name'].startswith(rule_prefix)
}


new_ips = cf_ips - set(existing_cf_rules.values())

stale_rules = {
    name: ip for name, ip in existing_cf_rules.items() if ip not in cf_ips
}

for rule_name in stale_rules:
    print(f"Deleting stale rule: {rule_name}")
    subprocess.run([
        "az", "network", "nsg", "rule", "delete",
        "--resource-group", resource_group,
        "--nsg-name", nsg_name,
        "--name", rule_name
    ])

result = subprocess.run([
    "az", "network", "nsg", "rule", "list",
    "--resource-group", resource_group,
    "--nsg-name", nsg_name,
    "--output", "json"
], capture_output=True, text=True)
existing_rules = json.loads(result.stdout)
existing_cf_rules = {
    rule['sourceAddressPrefix'] for rule in existing_rules
    if rule['name'].startswith(rule_prefix)
}

for idx, ip in enumerate(sorted(new_ips)):
    rule_name = f"{rule_prefix}{idx+1:03d}"
    priority = priority_start + idx

    if ip in existing_cf_rules:
        continue

    print(f"Adding new rule: {rule_name} for {ip}")

    subprocess.run([
        "az", "network", "nsg", "rule", "create",
        "--resource-group", resource_group,
        "--nsg-name", nsg_name,
        "--name", rule_name,
        "--priority", str(priority),
        "--direction", "Inbound",
        "--access", "Allow",
        "--protocol", "Tcp",
        "--source-address-prefixes", ip,
        "--destination-port-ranges", port,
        "--description", "Allow Cloudflare"
    ])

print("Done updating NSG rules.")
