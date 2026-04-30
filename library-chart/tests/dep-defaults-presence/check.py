#!/usr/bin/env python3
"""Assert every Helm dep declared in `library-chart/Chart.yaml` has a
matching `<chart>.enabled` default key in `library-chart/values.yaml`.

Why: see SPEC.md BEHAVIOR/dep-defaults-presence. Helm's `condition:
<chart>.enabled` is a NO-OP when the path is missing entirely from
values — the dep loads unconditionally. The redis dep added in #71
shipped this bug across 4 releases (0.11.4–0.11.6) before being caught
live and fixed in #75.

Layout: same as the other library-chart/tests/* (run.sh + check.py).
"""
import os
import sys

try:
    import yaml
except ImportError:
    sys.stderr.write(
        "PyYAML not installed; pip3 install pyyaml or python3 -m pip install pyyaml\n"
    )
    sys.exit(2)


def main() -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    chart_root = os.path.abspath(os.path.join(here, "..", ".."))
    chart_yaml_path = os.path.join(chart_root, "Chart.yaml")
    values_yaml_path = os.path.join(chart_root, "values.yaml")

    if not os.path.isfile(chart_yaml_path):
        sys.stderr.write(f"FAIL: missing {chart_yaml_path}\n")
        return 1
    if not os.path.isfile(values_yaml_path):
        sys.stderr.write(f"FAIL: missing {values_yaml_path}\n")
        return 1

    with open(chart_yaml_path) as f:
        chart = yaml.safe_load(f) or {}
    with open(values_yaml_path) as f:
        values = yaml.safe_load(f) or {}

    deps = chart.get("dependencies") or []
    if not deps:
        print("OK: no dependencies declared (vacuously true)")
        return 0

    missing = []
    wrong_type = []

    for dep in deps:
        name = dep.get("name")
        if not name:
            continue
        condition = dep.get("condition", "")
        # Only enforce on deps that gate on `<name>.enabled`. Deps with
        # no condition load unconditionally by design (and so don't need
        # the default); deps with a different condition path use that
        # path's default.
        if condition and condition != f"{name}.enabled":
            # Different gating path — skip this enforcement.
            continue

        block = values.get(name)
        if block is None:
            missing.append((name, "block missing entirely"))
            continue
        if not isinstance(block, dict):
            wrong_type.append((name, type(block).__name__))
            continue
        if "enabled" not in block:
            missing.append((name, f"`{name}.enabled` key missing"))
            continue

    if missing or wrong_type:
        sys.stderr.write(
            "FAIL: chart dependencies without an `<name>.enabled` default in "
            "values.yaml.\n"
            "Helm's `condition:` is a no-op when the path is missing — the "
            "dep loads unconditionally\n"
            "on every install. See SPEC.md BEHAVIOR/dep-defaults-presence.\n\n"
        )
        for name, why in missing:
            sys.stderr.write(f"  {name}: {why}\n")
        for name, t in wrong_type:
            sys.stderr.write(
                f"  {name}: top-level value is {t}, expected map with `enabled` key\n"
            )
        sys.stderr.write(
            "\nFix: add the missing default block(s) in library-chart/values.yaml:\n"
        )
        for name, _ in missing:
            sys.stderr.write(f"  {name}:\n    enabled: false\n")
        return 1

    print(f"OK: all {len(deps)} dependencies have `<name>.enabled` defaults in values.yaml")
    return 0


if __name__ == "__main__":
    sys.exit(main())
