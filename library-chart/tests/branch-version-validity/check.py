"""
branch-version-validity: verify every branch points to a real chart
in the AppCo OCI registry and uses the latest available version.
"""

import os
import sys
import yaml
import subprocess
import re

REGISTRY = "dp.apps.rancher.io"

def list_tags(chart_name):
    """List all version tags for a chart in AppCo."""
    try:
        result = subprocess.run(
            ["crane", "ls", f"{REGISTRY}/charts/{chart_name}"],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode != 0:
            return []
        tags = [t.strip() for t in result.stdout.strip().split("\n") if t.strip()]
        # Filter: only version tags (not sha256 sigs)
        return [t for t in tags if re.match(r"^\d+\.", t) and "sig" not in t]
    except Exception:
        return []

def get_app_version(chart_name, version):
    """Get the appVersion from a chart's metadata."""
    try:
        result = subprocess.run(
            ["helm", "show", "chart",
             f"oci://{REGISTRY}/charts/{chart_name}",
             "--version", version],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode != 0:
            return None
        for line in result.stdout.split("\n"):
            if line.startswith("appVersion:"):
                return line.split(":")[1].strip().strip('"')
        return None
    except Exception:
        return None

def version_key(v):
    """Sort key for semver-ish strings."""
    parts = re.split(r"[.\-]", v)
    return [int(p) if p.isdigit() else p for p in parts]

def find_latest_in_series(tags, prefix):
    """Find the latest tag matching a version prefix (e.g., '1.' for 1.x)."""
    matching = [t for t in tags if t.startswith(prefix)]
    if not matching:
        return None
    return sorted(matching, key=version_key)[-1]

def infer_branch_prefix(chart_name, branch, all_tags):
    """Infer which tag prefix corresponds to a branch.

    Convention: for SUSE-custom charts, the major chart version
    maps to an app version branch. We scan tags to find the mapping.
    """
    # For each chart, the branch maps to a chart version series:
    # postgresql: branch 16 → 0.2.x, 17 → 0.4.x, 18 → 0.5.x
    # redis: branch 7 → 1.x, 8 → 2.x
    # kafka: branch 3 → 0.x, 4 → 1.x
    # valkey: branch 7 → 0.1-0.4, 8 → 0.5-0.10, 9 → 0.11+
    #
    # We can't hardcode these — scan tags and match by appVersion.
    return None  # Caller uses brute-force scan

def main():
    lib_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    with open(os.path.join(lib_dir, "dsl-mappings.yaml")) as f:
        doc = yaml.safe_load(f)

    passed = 0
    failed = 0
    warnings = 0

    for chart_name, entry in sorted(doc["charts"].items()):
        branches = entry.get("branches", {})
        if not branches:
            continue

        sources = entry.get("sources", {})
        appco_ref = sources.get("appco", {}).get("chart_ref", f"oci://{REGISTRY}/charts/{chart_name}")
        # Extract actual chart name from OCI ref
        oci_chart = chart_name
        if "dex-idp" in appco_ref:
            oci_chart = "dex-idp"

        print(f"\n{chart_name}:")
        tags = list_tags(oci_chart)
        if not tags:
            print(f"  ⊘ could not list tags (crane/auth issue)")
            continue

        for branch, info in sorted(branches.items()):
            chart_version = info.get("chart_version", "")

            # 1. Check: does the chart_version exist?
            # Strip build suffix for matching (0.4.4-29.1 → match 0.4.4-29.1)
            if chart_version in tags:
                # Also check: is there a newer version in the same series?
                # Determine the series prefix from the chart_version
                parts = chart_version.split(".")
                if len(parts) >= 2:
                    prefix = parts[0] + "."
                    # For versions like 0.4.x, use two-part prefix
                    if parts[0] == "0":
                        prefix = "0." + parts[1][:1]  # 0.4 for 0.4.4
                    latest = find_latest_in_series(tags, prefix)

                    if latest and latest != chart_version:
                        base_latest = latest.split("-")[0] if "-" in latest else latest
                        base_current = chart_version.split("-")[0] if "-" in chart_version else chart_version
                        if base_latest != base_current:
                            print(f"  ⚠ branch {branch}: {chart_version} exists but {latest} is newer")
                            warnings += 1
                        else:
                            print(f"  ✓ branch {branch}: {chart_version} (latest in series)")
                            passed += 1
                    else:
                        print(f"  ✓ branch {branch}: {chart_version}")
                        passed += 1
                else:
                    print(f"  ✓ branch {branch}: {chart_version}")
                    passed += 1
            else:
                # Try without build suffix
                base = chart_version.split("-")[0] if "-" in chart_version else chart_version
                if base in tags:
                    print(f"  ✓ branch {branch}: {chart_version} (base {base} found)")
                    passed += 1
                else:
                    print(f"  ✗ branch {branch}: {chart_version} NOT FOUND in registry")
                    failed += 1

            # 2. Verify appVersion matches branch
            app_ver = get_app_version(oci_chart, chart_version)
            if app_ver:
                app_major = app_ver.split(".")[0]
                if app_major == branch or branch in app_ver:
                    pass  # matches
                else:
                    print(f"    ⚠ appVersion={app_ver} doesn't match branch={branch}")
                    warnings += 1

    print(f"\nResults: {passed} passed, {failed} failed, {warnings} warning(s)")
    return 1 if failed > 0 else 0

if __name__ == "__main__":
    sys.exit(main())
