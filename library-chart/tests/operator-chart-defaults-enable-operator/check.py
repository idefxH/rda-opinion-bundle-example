#!/usr/bin/env python3
"""
Regression guard for the "wrong sub-chart activated" bug pattern.

The bug shape (from cnpg's history — see commit cd440f4):
  - DSL type cnpg → renders Cluster CR via the library chart template
  - The CRDs + controller come from a separate sub-chart `cloudnative-pg`
  - `chart_defaults` must say `cloudnative-pg.enabled: true` so Helm
    pulls + installs the operator alongside the Cluster CR
  - If chart_defaults instead said `postgresql.enabled: true` (the
    Bitnami sub-chart), Helm would happily deploy a standalone
    PostgreSQL StatefulSet (wrong) while the Cluster CR fails to
    apply (no CRDs) — silent, confusing, took several iterations
    to track down the first time.

This check enforces, for every chart type marked `operator_managed`:
  1. `operator_resource` must reference a sub-chart (extracted from
     "{{ .Release.Name }}-<chart>") that is declared as a Chart.yaml
     dependency.
  2. `chart_defaults` must contain `<operator-chart>.enabled: true`
     so the operator + CRDs are actually installed.
  3. `chart_defaults` must NOT enable any OTHER chart from the same
     "family" of dependencies that could be mistaken for the
     operator's stack (e.g. the Bitnami `postgresql` sub-chart for
     a cnpg type). The whitelist of allowed `<x>.enabled` keys is:
       - the operator chart itself
       - the DSL type's own block (the library-chart-template gate,
         e.g. `cnpg.enabled` — set by the render engine; declaring it
         in chart_defaults is harmless and sometimes redundant)
"""
import os
import re
import sys

try:
    import yaml
except ImportError:
    sys.stderr.write(
        "PyYAML not installed; pip3 install pyyaml or python3 -m pip install pyyaml\n"
    )
    sys.exit(2)


REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MAPPING_FILE = os.path.join(REPO_ROOT, "dsl-mappings.yaml")
CHART_FILE = os.path.join(REPO_ROOT, "Chart.yaml")


def extract_chart_from_operator_resource(resource: str) -> str:
    """Pull the chart name out of '{{ .Release.Name }}-<chart>'.

    Returns "" if the template doesn't match the expected shape.
    """
    if not resource:
        return ""
    m = re.match(r"\{\{\s*\.Release\.Name\s*\}\}-(.+)$", resource.strip())
    return m.group(1).strip() if m else ""


def main() -> int:
    with open(MAPPING_FILE) as f:
        mapping = yaml.safe_load(f) or {}
    with open(CHART_FILE) as f:
        chart = yaml.safe_load(f) or {}

    dep_names = {
        (d.get("alias") or d.get("name"))
        for d in (chart.get("dependencies") or [])
        if d.get("name")
    }

    errors = []
    checked = 0

    for chart_name, entry in (mapping.get("charts") or {}).items():
        for i, ver in enumerate(entry.get("versions") or []):
            if not ver.get("operator_managed"):
                continue
            checked += 1
            path = f"charts.{chart_name}.versions[{i}]"

            operator_resource = ver.get("operator_resource") or ""
            operator_chart = extract_chart_from_operator_resource(operator_resource)
            if not operator_chart:
                errors.append(
                    f"{path}: operator_resource='{operator_resource}' — "
                    f"can't extract operator chart name from template "
                    f"(expected '{{{{ .Release.Name }}}}-<chart>')"
                )
                continue

            if operator_chart not in dep_names:
                errors.append(
                    f"{path}: operator chart '{operator_chart}' (from operator_resource) "
                    f"is not declared as a dependency in Chart.yaml"
                )

            cdefs = ver.get("chart_defaults") or {}
            enabled_key = f"{operator_chart}.enabled"
            if cdefs.get(enabled_key) is not True:
                errors.append(
                    f"{path}.chart_defaults: missing '{enabled_key}: true' — "
                    f"operator sub-chart won't be installed and the Cluster/CR "
                    f"will be rendered without CRDs. "
                    f"See commit cd440f4 for the original cnpg regression."
                )

            allowed_enable_keys = {enabled_key, f"{chart_name}.enabled"}
            for key, val in cdefs.items():
                if not key.endswith(".enabled"):
                    continue
                if val is not True:
                    continue
                if key in allowed_enable_keys:
                    continue
                if key in (f"{d}.enabled" for d in dep_names):
                    errors.append(
                        f"{path}.chart_defaults: enables foreign sub-chart "
                        f"'{key}' — operator_managed type '{chart_name}' should "
                        f"only enable '{enabled_key}' (its operator). "
                        f"Enabling a different chart here is the 'wrong sub-chart' "
                        f"bug pattern (e.g. cnpg accidentally turning on postgresql)."
                    )

    if errors:
        sys.stderr.write(
            "FAIL: operator-managed chart types missing or misconfigured "
            "chart_defaults for their operator sub-chart.\n\n"
        )
        for e in errors:
            sys.stderr.write("  " + e + "\n")
        return 1

    if checked == 0:
        print("SKIP: no operator_managed chart versions found")
        return 0

    print(
        f"OK: operator-chart-defaults-enable-operator: "
        f"{checked} operator-managed version(s) correctly enable their operator sub-chart"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
