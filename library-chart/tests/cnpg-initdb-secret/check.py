#!/usr/bin/env python3
"""
Verify that operator-managed database charts with auto-generated
credentials have a derived_value pointing initdb.secret.name (or
equivalent) to the binding secret.

Without this, the operator generates a random password that doesn't
match the binding secret — consumers (dex, airflow, app) fail with
"password authentication failed".

Currently checks: cnpg
"""
import os
import sys
import yaml

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MAPPING_FILE = os.path.join(REPO_ROOT, "dsl-mappings.yaml")

CHECKS = {
    "cnpg": {
        "derived_target_contains": "initdb.secret.name",
        "derived_template_contains": "-binding",
    },
}


def main():
    with open(MAPPING_FILE) as f:
        doc = yaml.safe_load(f)

    charts = doc.get("charts", {})
    errors = []
    checked = 0

    for chart_name, spec in CHECKS.items():
        entry = charts.get(chart_name)
        if not entry:
            errors.append(f"chart '{chart_name}' not found in dsl-mappings")
            continue

        versions = entry.get("versions", [])
        if not versions:
            errors.append(f"chart '{chart_name}' has no versions[]")
            continue

        ver = versions[0]
        derived = ver.get("derived_values", [])
        checked += 1

        target_needle = spec["derived_target_contains"]
        template_needle = spec["derived_template_contains"]

        found = False
        for dv in derived:
            if target_needle in dv.get("target", "") and template_needle in dv.get("template", ""):
                found = True
                break

        if not found:
            errors.append(
                f"chart '{chart_name}': no derived_value with "
                f"target containing '{target_needle}' and "
                f"template containing '{template_needle}' — "
                f"operator will auto-generate passwords that don't match the binding secret"
            )

    if errors:
        for e in errors:
            sys.stderr.write("ERROR: " + e + "\n")
        sys.exit(1)

    print(f"✓ cnpg-initdb-secret: {checked} chart(s) wire operator credentials to binding secret")


if __name__ == "__main__":
    main()
