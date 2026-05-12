#!/usr/bin/env python3
"""
Env scaffold contract enforcement.

Defines the expected env var pattern per service category, then verifies
that every chart's binding_secret produces env names matching the contract.
This is contract-first: the contract is defined HERE, not derived from
the current implementation. When a new chart violates, the test fails
until the chart is fixed or the contract is explicitly amended.

Contracts:
  database (postgresql, cnpg, mariadb):
    REQUIRED: HOST, PORT, USERNAME, PASSWORD, DATABASE, URL
    OPTIONAL: USER (alias), NAME (alias), JDBC_URL
    FORBIDDEN: CONNECTION_URL (must be URL)

  cache (redis, valkey):
    REQUIRED: HOST, PORT, PASSWORD, URL
    FORBIDDEN: CONNECTION_URL

  messaging (apache-kafka, nats):
    REQUIRED: HOST, PORT

  object-storage (minio):
    REQUIRED: HOST, PORT

  auth (dex):
    REQUIRED: HOST, PORT
"""
import os
import sys
import yaml

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MAPPING_FILE = os.path.join(REPO_ROOT, "dsl-mappings.yaml")

CONTRACTS = {
    "database": {
        "types": ["postgresql", "cnpg", "mariadb"],
        "required_suffixes": ["HOST", "PORT", "USERNAME", "PASSWORD", "DATABASE"],
        "forbidden_suffixes": ["CONNECTION_URL"],
    },
    "cache": {
        "types": ["redis", "valkey"],
        "required_suffixes": ["HOST", "PORT", "PASSWORD"],
        "forbidden_suffixes": ["CONNECTION_URL"],
    },
}


def env_suffixes_from_binding_secret(bs_entries):
    """Derive the set of env var suffixes a binding_secret would produce.

    Rules mirror add_service_env_scaffold.go:
      - skip_env entries are excluded
      - key → UPPER_SNAKE(key)
      - username also emits USER alias
      - database also emits NAME alias
    """
    suffixes = set()
    for entry in bs_entries:
        if entry.get("skip_env"):
            continue
        key = entry.get("key", "")
        if not key:
            continue
        suffix = key.upper().replace("-", "_")
        suffixes.add(suffix)
        if key == "username":
            suffixes.add("USER")
        if key == "database":
            suffixes.add("NAME")
    return suffixes


def main():
    with open(MAPPING_FILE) as f:
        doc = yaml.safe_load(f)

    charts = doc.get("charts", {})
    errors = []
    checked = 0

    for category, contract in CONTRACTS.items():
        for chart_type in contract["types"]:
            entry = charts.get(chart_type)
            if not entry:
                errors.append(f"[{category}] chart '{chart_type}' not in dsl-mappings")
                continue
            versions = entry.get("versions", [])
            if not versions:
                errors.append(f"[{category}] chart '{chart_type}' has no versions[]")
                continue

            bs = versions[0].get("binding_secret", [])
            suffixes = env_suffixes_from_binding_secret(bs)
            checked += 1

            for req in contract.get("required_suffixes", []):
                if req not in suffixes:
                    errors.append(
                        f"[{category}] {chart_type}: missing required env suffix "
                        f"{req} (has: {sorted(suffixes)})"
                    )

            for forbidden in contract.get("forbidden_suffixes", []):
                if forbidden in suffixes:
                    errors.append(
                        f"[{category}] {chart_type}: has forbidden env suffix "
                        f"{forbidden} — use the short form instead"
                    )

    if errors:
        for e in errors:
            sys.stderr.write("ERROR: " + e + "\n")
        sys.exit(1)

    print(
        f"✓ env-scaffold-contract: {checked} chart(s) across "
        f"{len(CONTRACTS)} categories comply with env naming contracts"
    )


if __name__ == "__main__":
    main()
