#!/usr/bin/env python3
"""Switch library-chart/Chart.yaml between 'appco' and 'community' mode.

community mode: drops every dep whose repository is on
  oci://dp.apps.rancher.io (the SUSE Application Collection). The
  resulting Chart.yaml lets `helm dep update` succeed without any
  AppCo registry credentials. The dropped names are reconstructible
  from scripts/appco-overlay.yaml.

appco mode: restores the dropped deps by appending entries from
  scripts/appco-overlay.yaml. Idempotent — already-present deps are
  not duplicated.

--check: exit non-zero if appco-overlay.yaml and Chart.yaml have
  drifted (different name/version/repository for any shared dep).
  Used by tests/ to catch a stale overlay before CI does.

Why this exists:
  `helm dep update` resolves every dependency in Chart.yaml regardless
  of its `condition:` gate — the gate only controls install-time
  rendering. AppCo OCI repos require `helm registry login`, which CI
  and community users cannot provide. Stripping those deps lets the
  bundle render against community charts only. The CI used to do this
  with sed; this script makes it a first-class bundle operation.
"""

import argparse
import os
import re
import sys
from typing import List, Tuple

try:
    import yaml
except ImportError:
    sys.stderr.write(
        "chart-source: PyYAML is required. Install with `pip install pyyaml`.\n"
    )
    sys.exit(2)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
LIB_DIR = os.path.dirname(SCRIPT_DIR)
CHART_PATH = os.path.join(LIB_DIR, "Chart.yaml")
OVERLAY_PATH = os.path.join(SCRIPT_DIR, "appco-overlay.yaml")

APPCO_OCI_PREFIX = "oci://dp.apps.rancher.io"


def load_yaml(path: str) -> dict:
    with open(path) as f:
        return yaml.safe_load(f)


def appco_deps_in(chart: dict) -> List[dict]:
    return [
        d
        for d in chart.get("dependencies", [])
        if (d.get("repository") or "").startswith(APPCO_OCI_PREFIX)
    ]


def strip_dep_block(text: str, name: str) -> Tuple[str, int]:
    """Delete the 4-line `- name: <name>` block. Returns (text, count)."""
    pat = re.compile(
        rf"^  - name: {re.escape(name)}$\n"
        rf"    version: .*\n"
        rf"    repository: .*\n"
        rf"    condition: .*\n",
        re.MULTILINE,
    )
    return pat.subn("", text)


def render_dep_block(dep: dict) -> str:
    return (
        f"  - name: {dep['name']}\n"
        f"    version: \"{dep['version']}\"\n"
        f"    repository: {dep['repository']}\n"
        f"    condition: {dep['condition']}\n"
    )


def check_overlay_matches(chart: dict, overlay: dict) -> List[str]:
    """Return a list of drift messages between Chart.yaml's AppCo block
    and the overlay file. Empty list = in sync."""
    by_name_chart = {d["name"]: d for d in appco_deps_in(chart)}
    by_name_over = {d["name"]: d for d in overlay.get("dependencies", [])}
    drift = []
    for name in sorted(set(by_name_chart) | set(by_name_over)):
        c = by_name_chart.get(name)
        o = by_name_over.get(name)
        if c is None:
            drift.append(f"{name}: in overlay but missing from Chart.yaml")
            continue
        if o is None:
            drift.append(f"{name}: in Chart.yaml but missing from overlay")
            continue
        for k in ("version", "repository", "condition"):
            if str(c.get(k)) != str(o.get(k)):
                drift.append(
                    f"{name}.{k}: Chart.yaml={c.get(k)!r} overlay={o.get(k)!r}"
                )
    return drift


def go_community(chart_path: str, chart_text: str, chart: dict) -> int:
    deps = appco_deps_in(chart)
    if not deps:
        print("chart-source: already in community mode — no AppCo OCI deps to strip.")
        return 0
    new_text = chart_text
    for d in deps:
        new_text, n = strip_dep_block(new_text, d["name"])
        if n != 1:
            sys.stderr.write(
                f"chart-source: expected 1 dep block for {d['name']!r}, found {n}. "
                f"Chart.yaml may have been hand-edited; aborting.\n"
            )
            return 3
    with open(chart_path, "w") as f:
        f.write(new_text)
    print(
        f"chart-source: removed {len(deps)} AppCo OCI dep(s) "
        f"({', '.join(d['name'] for d in deps)}). "
        f"Reverse with `python3 {os.path.relpath(__file__, os.getcwd())} --mode appco`."
    )
    return 0


def go_appco(chart_path: str, chart_text: str, chart: dict, overlay: dict) -> int:
    present = {d["name"] for d in chart.get("dependencies", [])}
    missing = [d for d in overlay.get("dependencies", []) if d["name"] not in present]
    if not missing:
        print("chart-source: already in appco mode — all overlay deps present.")
        return 0
    # Append each missing block at end of dependencies list (preserves
    # all comments above). Chart.yaml ends with a final newline; we
    # append blocks immediately before any trailing whitespace.
    tail_match = re.search(r"\n+\Z", chart_text)
    tail = tail_match.group(0) if tail_match else "\n"
    body = chart_text[: tail_match.start()] if tail_match else chart_text
    body += "\n" + "".join(render_dep_block(d) for d in missing).rstrip("\n") + tail
    with open(chart_path, "w") as f:
        f.write(body)
    print(
        f"chart-source: restored {len(missing)} AppCo OCI dep(s) "
        f"({', '.join(d['name'] for d in missing)}) from "
        f"{os.path.relpath(OVERLAY_PATH, os.getcwd())}."
    )
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--mode", choices=["community", "appco"], help="Target chart source.")
    g.add_argument("--check", action="store_true", help="Verify Chart.yaml and appco-overlay.yaml are in sync.")
    ap.add_argument("--chart", default=CHART_PATH, help="Path to Chart.yaml (default: library-chart/Chart.yaml).")
    ap.add_argument("--overlay", default=OVERLAY_PATH, help="Path to appco-overlay.yaml.")
    args = ap.parse_args()

    with open(args.chart) as f:
        chart_text = f.read()
    chart = yaml.safe_load(chart_text)
    overlay = load_yaml(args.overlay)

    if args.check:
        drift = check_overlay_matches(chart, overlay)
        if drift:
            sys.stderr.write("chart-source: appco-overlay.yaml has drifted from Chart.yaml:\n")
            for d in drift:
                sys.stderr.write(f"  - {d}\n")
            sys.stderr.write(
                "Fix by editing appco-overlay.yaml to match the AppCo "
                "block in Chart.yaml, or vice versa.\n"
            )
            return 1
        print("chart-source: appco-overlay.yaml and Chart.yaml are in sync.")
        return 0

    if args.mode == "community":
        return go_community(args.chart, chart_text, chart)
    return go_appco(args.chart, chart_text, chart, overlay)


if __name__ == "__main__":
    sys.exit(main())
