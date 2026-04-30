#!/usr/bin/env python3
"""Assert that library-chart/Chart.yaml's version matches rda-bundle.yaml's
library_chart.version.

Why this test exists: rda CLI's `rda upgrade` reads the target version
from the bundle's `rda-bundle.yaml` manifest (the canonical bundle
declaration), NOT from `library-chart/Chart.yaml` directly. If the two
drift, `rda upgrade` silently lies — it'll say "already up to date" at
the manifest's stale version while the actual library is newer.

This bug shipped through 4 consecutive bundle releases (0.11.5/6/7/8)
because nothing in the contributor flow caught the missing manifest
bump. This test makes the next miss fail loud at PR review time.

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
    # Resolve the bundle root from this script's location.
    # check.py lives at library-chart/tests/manifest-version-sync/check.py;
    # bundle root is three levels up.
    here = os.path.dirname(os.path.abspath(__file__))
    bundle_root = os.path.abspath(os.path.join(here, "..", "..", ".."))

    chart_yaml_path = os.path.join(bundle_root, "library-chart", "Chart.yaml")
    manifest_path = os.path.join(bundle_root, "rda-bundle.yaml")

    if not os.path.isfile(chart_yaml_path):
        sys.stderr.write(f"FAIL: missing {chart_yaml_path}\n")
        return 1
    if not os.path.isfile(manifest_path):
        sys.stderr.write(f"FAIL: missing {manifest_path}\n")
        return 1

    with open(chart_yaml_path) as f:
        chart = yaml.safe_load(f) or {}
    with open(manifest_path) as f:
        manifest = yaml.safe_load(f) or {}

    chart_version = str(chart.get("version", "")).strip()
    manifest_version = str(
        ((manifest.get("library_chart") or {}).get("version") or "")
    ).strip()

    if not chart_version:
        sys.stderr.write(
            "FAIL: library-chart/Chart.yaml has no `version` field\n"
        )
        return 1
    if not manifest_version:
        sys.stderr.write(
            "FAIL: rda-bundle.yaml has no `library_chart.version` field\n"
        )
        return 1

    if chart_version != manifest_version:
        sys.stderr.write(
            "FAIL: library-chart/Chart.yaml.version != rda-bundle.yaml.library_chart.version\n"
            f"  library-chart/Chart.yaml: {chart_version}\n"
            f"  rda-bundle.yaml:          {manifest_version}\n"
            "\n"
            "These two MUST match. `rda upgrade` reads the manifest's library_chart.version\n"
            "to compute the target — drift makes it silently report 'already up to date' at\n"
            "the manifest's stale version while the actual library is newer.\n"
            "\n"
            "Fix: bump rda-bundle.yaml's library_chart.version to match the chart's version,\n"
            "in the SAME commit that bumps library-chart/Chart.yaml. See CONTRIBUTING.md.\n"
        )
        return 1

    print(f"OK: library_chart.version is {chart_version} in both Chart.yaml and rda-bundle.yaml")
    return 0


if __name__ == "__main__":
    sys.exit(main())
