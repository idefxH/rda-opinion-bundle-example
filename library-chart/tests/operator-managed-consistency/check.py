#!/usr/bin/env python3
"""
For every chart version with operator_managed: true, verify that
all required companion fields are present:
  - cr_kind (with kind + api_version)
  - cr_object
  - pod_selector (non-empty)
  - operator_resource

A missing field means the Tilt extension can't properly register
the CRD kind, claim the CR object, discover operator-created pods,
or order deployment after the operator.
"""
import os
import sys
import yaml

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MAPPING_FILE = os.path.join(REPO_ROOT, "dsl-mappings.yaml")

REQUIRED_FIELDS = ["cr_kind", "cr_object", "pod_selector", "operator_resource"]
CR_KIND_FIELDS = ["kind", "api_version"]


def main():
    with open(MAPPING_FILE) as f:
        doc = yaml.safe_load(f)

    charts = doc.get("charts", {})
    errors = []
    checked = 0

    for chart_name, entry in charts.items():
        for i, ver in enumerate(entry.get("versions", [])):
            if not ver.get("operator_managed"):
                continue
            checked += 1
            path = f"charts.{chart_name}.versions[{i}]"

            for field in REQUIRED_FIELDS:
                val = ver.get(field)
                if not val:
                    errors.append(f"{path}: operator_managed=true but missing '{field}'")

            cr_kind = ver.get("cr_kind", {})
            if cr_kind:
                for kf in CR_KIND_FIELDS:
                    if not cr_kind.get(kf):
                        errors.append(f"{path}.cr_kind: missing '{kf}'")

    if errors:
        for e in errors:
            sys.stderr.write("ERROR: " + e + "\n")
        sys.exit(1)

    if checked == 0:
        print("SKIP: no operator_managed charts found")
    else:
        print(f"✓ operator-managed-consistency: {checked} operator-managed version(s) have all required fields")


if __name__ == "__main__":
    main()
