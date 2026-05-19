#!/usr/bin/env python3
"""Assert that every templates/*/deploy/Chart.yaml carries the SAME
library-chart version as library-chart/Chart.yaml — both the chart's
own `version:` line and its `suse-library` dependency pin.

Why this test exists: fresh `rda new` projects vendor the library chart
at the version pinned in their template's `Chart.yaml`. If that pin
lags the canonical library-chart/Chart.yaml, every project scaffolded
during the drift window ends up on the OLD library chart even though
the bundle is at the NEW one. The bug is invisible at scaffold time
(helm dep update happily resolves the old pin from file://library-chart
because file:// just uses what's on disk — version assertions are not
re-checked once the local copy is found), so the only signal is a
behavior regression days later.

We had drift between 0.16.x library-chart and 0.16.0 templates. This
test makes the next miss fail at PR review.

The template files are Go-templated (they contain `{{ .Name }}` etc.),
so they're not valid YAML — we parse them line-by-line with regex
instead of yaml.safe_load.

Layout: same as the other library-chart/tests/* (run.sh + check.py).
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


# Top-level `version:` line. Matches both quoted (`version: "0.16.0"`)
# and unquoted (`version: 0.16.0`). Anchored at start-of-line so we
# don't pick up the dep version (which is indented).
TOP_VERSION_RE = re.compile(r'^version:\s*"?([^"\s]+)"?\s*$')

# `name: suse-library` then the next `version:` line within the same
# dependency entry. We scan the file line by line; when we see the
# suse-library name marker, we capture the next version line we hit.
SUSE_DEP_NAME_RE = re.compile(r'^\s*-?\s*name:\s*suse-library\s*$')
DEP_VERSION_RE = re.compile(r'^\s*version:\s*"?([^"\s]+)"?\s*$')


def extract_template_versions(path: str):
    """Return (chart_version, suse_dep_version) tuple; either may be None
    if the line wasn't found."""
    chart_version = None
    suse_dep_version = None
    looking_for_dep_version = False
    with open(path) as f:
        for line in f:
            if chart_version is None:
                m = TOP_VERSION_RE.match(line)
                if m:
                    chart_version = m.group(1)
                    continue
            if SUSE_DEP_NAME_RE.match(line):
                looking_for_dep_version = True
                continue
            if looking_for_dep_version:
                m = DEP_VERSION_RE.match(line)
                if m:
                    suse_dep_version = m.group(1)
                    looking_for_dep_version = False
    return chart_version, suse_dep_version


def main() -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    bundle_root = os.path.abspath(os.path.join(here, "..", "..", ".."))

    chart_yaml_path = os.path.join(bundle_root, "library-chart", "Chart.yaml")
    templates_dir = os.path.join(bundle_root, "templates")

    if not os.path.isfile(chart_yaml_path):
        sys.stderr.write(f"FAIL: missing {chart_yaml_path}\n")
        return 1
    if not os.path.isdir(templates_dir):
        sys.stderr.write(f"FAIL: missing templates dir at {templates_dir}\n")
        return 1

    with open(chart_yaml_path) as f:
        chart = yaml.safe_load(f) or {}
    canonical = str(chart.get("version", "")).strip()
    if not canonical:
        sys.stderr.write(
            "FAIL: library-chart/Chart.yaml has no `version` field\n"
        )
        return 1

    # Walk templates/*/deploy/Chart.yaml. We don't blindly glob — a
    # template without a deploy/Chart.yaml (e.g. brownfield-helm, which
    # only ships the values block) is legitimately exempt. We REQUIRE
    # the file to either be missing entirely or, if present, match.
    template_charts = []
    for entry in sorted(os.listdir(templates_dir)):
        candidate = os.path.join(templates_dir, entry, "deploy", "Chart.yaml")
        if os.path.isfile(candidate):
            template_charts.append(candidate)

    if not template_charts:
        sys.stderr.write(
            f"FAIL: no templates/*/deploy/Chart.yaml found under {templates_dir} — "
            "this test expects at least one templated chart to exist\n"
        )
        return 1

    failures = []
    for path in template_charts:
        rel = os.path.relpath(path, bundle_root)
        chart_version, dep_version = extract_template_versions(path)

        if chart_version is None:
            failures.append(
                f"{rel}: no top-level `version:` line found"
            )
        elif chart_version != canonical:
            failures.append(
                f"{rel}: chart version `{chart_version}` "
                f"!= library-chart `{canonical}`"
            )

        if dep_version is None:
            failures.append(
                f"{rel}: no `suse-library` dependency version found"
            )
        elif dep_version != canonical:
            failures.append(
                f"{rel}: suse-library dep pin `{dep_version}` "
                f"!= library-chart `{canonical}`"
            )

    if failures:
        sys.stderr.write(
            "FAIL: template(s) pin a different library-chart version than "
            f"library-chart/Chart.yaml ({canonical}).\n\n"
        )
        for line in failures:
            sys.stderr.write(f"  {line}\n")
        sys.stderr.write(
            "\nFresh `rda new` projects vendor the library chart at the pin in "
            "their template's Chart.yaml.\n"
            "Drift here means new projects scaffold with the wrong library "
            "version — invisible at scaffold time,\n"
            "surfaces days later as a behavior regression.\n\n"
            "Fix: run `bash scripts/bump-version.sh "
            f"{canonical}` to align everything in one shot,\n"
            "or edit the offending Chart.yaml manually.\n"
        )
        return 1

    print(
        f"OK: all {len(template_charts)} templates/*/deploy/Chart.yaml pin "
        f"library-chart version {canonical}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
