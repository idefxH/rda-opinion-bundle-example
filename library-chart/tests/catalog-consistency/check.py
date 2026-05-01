#!/usr/bin/env python3
"""
Cross-repo consistency check between this bundle's
`library-chart/dsl-mappings.yaml` and rda-docs's
`reference/catalog.md` documentation.

Invariant enforced (the directional one — the only one that matters
for "drift"):

  Every chart catalogued in dsl-mappings.yaml MUST appear as a row in
  the `## Catalogued charts` table of reference/catalog.md.

This catches the classic drift case: a bundle PR adds a helper for a
new chart in dsl-mappings.yaml but forgets to land the corresponding
docs PR in rda-docs. The CLI auto-discovers the chart (rda-cli
>=0.1.26 reads the YAML), so the user experience would be "`rda
add-service newchart payments` works but `rda explain` and the
operator-facing docs show no curated entry". The CI fails noisily
before that happens.

The reverse direction (catalog.md -> YAML) is intentionally NOT
enforced: charts may appear in catalog.md ahead of their helpers
landing in dsl-mappings.yaml (the doc preview pattern). That asymmetry
is informational, not a CI failure.

Usage:
  CATALOG_MD_PATH=path/to/catalog.md ./check.py
  ./check.py            # defaults to ../../../../rda-docs/reference/catalog.md

Environment:
  CATALOG_MD_PATH — explicit path to reference/catalog.md (CI uses the
                    cloned rda-docs workspace directly).

Exit codes:
  0  consistent
  1  drift detected (chart in YAML missing from catalog.md table)
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
    os.path.join(REPO_ROOT, "..", "..", "rda-docs", "reference", "catalog.md")
)

# The section heading whose immediately-following table is the
# canonical chart list. If the reference/catalog.md restructure ever
# moves the table under a different heading, update this constant.
CATALOG_SECTION = "## Catalogued charts"


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


def chart_names_from_catalog(path):
    """Return the set of chart names listed in the `## Catalogued charts`
    table of reference/catalog.md.

    Parsing strategy: find the first line equal to CATALOG_SECTION, then
    walk forward collecting markdown table rows (lines starting with
    `|`) until we hit a blank-line-then-non-table or the next `## `
    heading. Skip the header row (`| Type | ...`) and the separator
    (`|---|---|...`). The first cell of each remaining row is the chart
    name, conventionally wrapped in backticks (e.g. `` `postgresql` ``).
    """
    if not os.path.isfile(path):
        sys.stderr.write("ERROR: catalog.md not found at %s\n" % path)
        sys.stderr.write("       Set CATALOG_MD_PATH or place a clone of rda-docs at ../rda-docs\n")
        return None

    in_section = False
    in_table = False
    rows_seen = 0  # we skip the first 2: header + separator
    charts = set()

    with open(path) as f:
        for raw in f:
            line = raw.rstrip("\n")
            stripped = line.strip()

            if not in_section:
                if stripped == CATALOG_SECTION:
                    in_section = True
                continue

            # Stop at the next H2 heading.
            if stripped.startswith("## ") and stripped != CATALOG_SECTION:
                break

            if stripped.startswith("|"):
                in_table = True
                rows_seen += 1
                # row 1 = header, row 2 = `|---|---|...` separator.
                if rows_seen <= 2:
                    continue
                cells = [c.strip() for c in stripped.strip("|").split("|")]
                if not cells:
                    continue
                # Strip surrounding backticks from the first cell.
                name = cells[0].strip("`").strip()
                if name:
                    charts.add(name)
            elif in_table and stripped == "":
                # Blank line after the table = table is done; keep
                # scanning until the next H2 in case the section has
                # follow-up prose, but no more table rows are expected.
                in_table = False

    if not in_section:
        sys.stderr.write("ERROR: no `%s` heading found in %s\n" % (CATALOG_SECTION, path))
        sys.stderr.write("       The doc structure changed — update CATALOG_SECTION in this script.\n")
        return None

    return charts


def main():
    catalog_path = os.environ.get("CATALOG_MD_PATH", DEFAULT_CATALOG_PATH)

    yaml_charts = chart_names_from_mapping(MAPPING_FILE)
    if yaml_charts is None:
        return 2
    catalog_charts = chart_names_from_catalog(catalog_path)
    if catalog_charts is None:
        return 2

    # The single invariant: YAML ⊆ catalog.md.
    missing_in_catalog = sorted(yaml_charts - catalog_charts)

    # Informational: charts documented but not yet in YAML. Reported
    # but does NOT fail the check (intentional asymmetry, see header).
    only_in_catalog = sorted(catalog_charts - yaml_charts)

    if missing_in_catalog:
        print("✗ catalog-consistency: drift detected", file=sys.stderr)
        print("", file=sys.stderr)
        print("Charts catalogued in %s but missing from %s:" %
              (os.path.relpath(MAPPING_FILE), os.path.relpath(catalog_path)), file=sys.stderr)
        for name in missing_in_catalog:
            print("  - %s" % name, file=sys.stderr)
        print("", file=sys.stderr)
        print("Add a row for `%s` to the `## Catalogued charts` table in %s" %
              (missing_in_catalog[0], catalog_path), file=sys.stderr)
        print("(and a corresponding column in `## Per-chart DSL surface` below it).", file=sys.stderr)
        return 1

    print("✓ catalog-consistency: %d chart(s) catalogued in dsl-mappings.yaml all have catalog.md rows" %
          len(yaml_charts))
    if only_in_catalog:
        print("  (informational: %d chart(s) listed in catalog.md but not yet in dsl-mappings.yaml: %s)" %
              (len(only_in_catalog), ", ".join(only_in_catalog)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
