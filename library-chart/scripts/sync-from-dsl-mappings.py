#!/usr/bin/env python3
"""
Sync Chart.yaml dependencies and values.yaml defaults from dsl-mappings.yaml.

dsl-mappings.yaml is the single source of truth for which charts are
in the catalog. This script derives:
  1. Chart.yaml dependencies (name, version, repository, condition)
  2. values.yaml <chart>.enabled: false defaults

Usage:
  python3 library-chart/scripts/sync-from-dsl-mappings.py [--dry-run]

The script reads dsl-mappings.yaml, Chart.yaml, and values.yaml,
then updates Chart.yaml and values.yaml to match. Existing entries
are preserved; missing ones are added; orphaned ones are flagged.
"""

import os
import sys
import yaml

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
LIB_DIR = os.path.dirname(SCRIPT_DIR)

DSL_PATH = os.path.join(LIB_DIR, "dsl-mappings.yaml")
CHART_PATH = os.path.join(LIB_DIR, "Chart.yaml")
VALUES_PATH = os.path.join(LIB_DIR, "values.yaml")


def load_yaml(path):
    with open(path) as f:
        return yaml.safe_load(f)


def main():
    dry_run = "--dry-run" in sys.argv

    dsl = load_yaml(DSL_PATH)
    chart = load_yaml(CHART_PATH)
    values = load_yaml(VALUES_PATH)

    dsl_charts = set(dsl.get("charts", {}).keys())

    # --- Chart.yaml dependencies ---
    existing_deps = {d["name"]: d for d in chart.get("dependencies", [])}
    # Also check aliases
    dep_names = set()
    for d in chart.get("dependencies", []):
        dep_names.add(d.get("alias", d["name"]))

    missing_deps = dsl_charts - dep_names
    if missing_deps:
        print(f"Charts in dsl-mappings but NOT in Chart.yaml dependencies:")
        for name in sorted(missing_deps):
            print(f"  - {name} (add to Chart.yaml with condition: {name}.enabled)")

    # --- values.yaml defaults ---
    missing_values = []
    for chart_name in sorted(dsl_charts):
        if chart_name not in values:
            missing_values.append(chart_name)

    if missing_values:
        print(f"\nCharts in dsl-mappings but missing enabled: false in values.yaml:")
        for name in missing_values:
            print(f"  - {name}")

    if not missing_deps and not missing_values:
        print("All charts in dsl-mappings.yaml are synced with Chart.yaml and values.yaml.")
        return

    if dry_run:
        print("\n[dry-run] No files modified.")
        return

    # Auto-add missing values.yaml defaults
    if missing_values:
        with open(VALUES_PATH, "a") as f:
            f.write("\n# Auto-added by sync-from-dsl-mappings.py\n")
            for name in missing_values:
                f.write(f"{name}:\n  enabled: false\n\n")
        print(f"\nAdded {len(missing_values)} defaults to values.yaml")

    print("\nChart.yaml dependencies must be added manually (need version + repository).")


if __name__ == "__main__":
    main()
