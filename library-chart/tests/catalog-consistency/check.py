#!/usr/bin/env python3
"""
Cross-repo consistency check between this bundle's
`library-chart/dsl-mappings.yaml` and the rda-devx-catalog's
`CATALOG.md` documentation.

Invariant enforced (the directional one — the only one that
matters for "drift"):

  Every chart catalogued in dsl-mappings.yaml MUST have a matching
  `## <chart-name>` heading in CATALOG.md.

This catches the classic drift case: a bundle PR adds a helper for a
new chart in dsl-mappings.yaml but forgets to land the corresponding
docs PR in rda-devx-catalog. The CLI now auto-discovers the chart
(rda-cli >=0.1.26 reads the YAML), so the user experience would be
"`rda add-service newchart payments` works but `--help` / `rda
explain` show no curated docs". The CI fails noisily before that
happens.

The reverse direction (CATALOG.md -> YAML) is intentionally NOT
enforced: CATALOG.md describes the full Tier 1 + Tier 2 + Tier 3 +
out-of-scope landscape, including charts marked "🟡 in flight"
that have docs but not yet helpers (e.g. valkey, prometheus when
their helpers are still on a feature branch). That asymmetry is
informational, not a CI failure.

Usage:
  CATALOG_MD_PATH=path/to/CATALOG.md ./check.py
  ./check.py            # defaults to ../../../../rda-devx-catalog/CATALOG.md

Environment:
  CATALOG_MD_PATH — explicit path to CATALOG.md (CI uses the cloned
                    rda-devx-catalog workspace directly).

Exit codes:
  0  consistent
  1  drift detected (chart in YAML missing from CATALOG.md, etc.)
  2  prerequisite missing (PyYAML, file not found)
"""
import os
import re
import sys

try:
    import yaml
except ImportError:
    sys.stderr.write("PyYAML not installed; pip3 install pyyaml or use python3 -m pip install pyyaml\n")
    sys.exit(2)

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MAPPING_FILE = os.path.join(REPO_ROOT, "dsl-mappings.yaml")

# Default path: a sibling clone alongside this repo. Matches the
# layout devs use locally (one ~/Documents/GitHub/<repo> per repo);
# CI overrides via the env var to point at whatever directory the
# checkout step uses.
DEFAULT_CATALOG_PATH = os.path.normpath(
    os.path.join(REPO_ROOT, "..", "..", "rda-devx-catalog", "CATALOG.md")
)


def chart_names_from_mapping(path):
    """Extract the set of chart names catalogued in dsl-mappings.yaml.

    Tolerates malformed entries: returns an empty set rather than raising,
    because the schema validator (../dsl-mappings-schema/check.py) is the
    right place to surface that. We just need the chart-name keys.
    """
    if not os.path.isfile(path):
        sys.stderr.write("ERROR: dsl-mappings.yaml not found at %s\n" % path)
        return None
    with open(path) as f:
        try:
            doc = yaml.safe_load(f)
        except yaml.YAMLError as e:
            sys.stderr.write("ERROR: parse %s: %s\n" % (path, e))
            return None
    if not isinstance(doc, dict):
        return set()
    charts = doc.get("charts")
    if not isinstance(charts, dict):
        return set()
    return set(charts.keys())


# Headings that appear as `## <something>` in CATALOG.md but are NOT
# chart-section headers. Hardcoded to keep the parser simple — the
# alternative (heuristics like "lowercase no spaces") drifts as the
# doc evolves. Adding a new non-chart heading means a one-line append
# here AND a CI rerun.
NON_CHART_HEADINGS = frozenset({
    "format",
    "catalogue tiers",
    "to add (stub)",
})


def chart_sections_from_catalog(path):
    """Return the set of chart names that have a `## <name>` section in
    CATALOG.md, excluding known non-chart headings (Format, Catalogue
    tiers, etc.).

    A chart heading is matched by a line starting with exactly two `#`
    followed by a single token (the chart name). We deliberately ignore
    `### <name>` (Tier sub-headings) and `# <name>` (the doc title).
    """
    if not os.path.isfile(path):
        sys.stderr.write("ERROR: CATALOG.md not found at %s\n" % path)
        sys.stderr.write("       Set CATALOG_MD_PATH or place a clone of rda-devx-catalog at ../rda-devx-catalog\n")
        return None
    sections = set()
    h2 = re.compile(r"^## ([^\n]+?)\s*$")
    with open(path) as f:
        for line in f:
            m = h2.match(line)
            if not m:
                continue
            heading = m.group(1).strip()
            if heading.lower() in NON_CHART_HEADINGS:
                continue
            sections.add(heading)
    return sections


def main():
    catalog_path = os.environ.get("CATALOG_MD_PATH", DEFAULT_CATALOG_PATH)

    yaml_charts = chart_names_from_mapping(MAPPING_FILE)
    if yaml_charts is None:
        return 2
    catalog_charts = chart_sections_from_catalog(catalog_path)
    if catalog_charts is None:
        return 2

    # The single invariant: YAML ⊆ CATALOG.
    missing_in_catalog = sorted(yaml_charts - catalog_charts)

    # Informational: charts documented but not yet in YAML. Reported
    # but does NOT fail the check (intentional asymmetry, see header).
    only_in_catalog = sorted(catalog_charts - yaml_charts)

    if missing_in_catalog:
        print("✗ catalog-consistency: drift detected", file=sys.stderr)
        print("", file=sys.stderr)
        print("Charts catalogued in %s but missing from CATALOG.md:" % os.path.relpath(MAPPING_FILE), file=sys.stderr)
        for name in missing_in_catalog:
            print("  - %s" % name, file=sys.stderr)
        print("", file=sys.stderr)
        print("Add a `## %s` section to %s with the 12-dimension spec." %
              (missing_in_catalog[0], catalog_path), file=sys.stderr)
        print("", file=sys.stderr)
        print("(See existing chart sections like `## postgresql` for the template.)", file=sys.stderr)
        return 1

    print("✓ catalog-consistency: %d chart(s) catalogued in dsl-mappings.yaml all have CATALOG.md sections" %
          len(yaml_charts))
    if only_in_catalog:
        print("  (informational: %d chart(s) documented in CATALOG.md but not yet in dsl-mappings.yaml — likely 🟡 in flight: %s)" %
              (len(only_in_catalog), ", ".join(only_in_catalog)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
