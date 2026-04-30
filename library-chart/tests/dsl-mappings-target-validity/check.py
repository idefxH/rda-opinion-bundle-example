#!/usr/bin/env python3
"""Assert every values_mapping target path in dsl-mappings.yaml parses
under the bracket-notation rules `rda render` enforces.

Why: see SPEC.md BEHAVIOR/dsl-mappings-target-validity. The projection
package in rda-cli (internal/render/projection.go) walks each target
path component-by-component:
- segments separated by `.`
- each segment is either `name` (map key) or `name[N]` (list index)
- malformed brackets (`name[`, `name[]`, `name[abc]`) are rejected loud

A typo in dsl-mappings.yaml (e.g. `hosts[0]a` or `chart..auth`) would
silently fail at render time — values_mapping rule skipped, the field
isn't projected, helm renders a chart without that value, runtime
failure with no clear pointer back to the mapping. This test catches
the typo at PR review.

Layout: same as the other library-chart/tests/* (run.sh + check.py).
"""
import os
import re
import sys
from typing import Optional

try:
    import yaml
except ImportError:
    sys.stderr.write(
        "PyYAML not installed; pip3 install pyyaml or python3 -m pip install pyyaml\n"
    )
    sys.exit(2)


# Per-segment shape: name OR name[N] where N is non-negative integer.
SEGMENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_-]*(?:\[[0-9]+\])?$")
DOUBLE_DOT_RE = re.compile(r"\.\.")
EMPTY_BRACKET_RE = re.compile(r"\[\]")
NON_NUMERIC_BRACKET_RE = re.compile(r"\[[^0-9\]][^\]]*\]")


def validate_path(path: str) -> Optional[str]:
    """Return None when valid, error string when not."""
    if not path:
        return "empty path"
    if path.startswith(".") or path.endswith("."):
        return f"leading or trailing dot in {path!r}"
    if DOUBLE_DOT_RE.search(path):
        return f"empty segment (double dot) in {path!r}"
    if EMPTY_BRACKET_RE.search(path):
        return f"empty bracket `[]` in {path!r}"
    if NON_NUMERIC_BRACKET_RE.search(path):
        return f"non-numeric bracket index in {path!r}"
    for seg in path.split("."):
        if not seg:
            return f"empty segment in {path!r}"
        if not SEGMENT_RE.fullmatch(seg):
            return f"invalid segment {seg!r} in {path!r}"
    return None


def main() -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    mappings_path = os.path.abspath(
        os.path.join(here, "..", "..", "dsl-mappings.yaml")
    )

    if not os.path.isfile(mappings_path):
        sys.stderr.write(f"FAIL: missing {mappings_path}\n")
        return 1

    with open(mappings_path) as f:
        doc = yaml.safe_load(f) or {}

    failures = []
    paths_checked = 0
    charts = doc.get("charts") or {}

    for chart_name, entry in charts.items():
        for vidx, version in enumerate(entry.get("versions") or []):
            mapping = version.get("values_mapping") or {}
            for dsl_path, target_path in mapping.items():
                paths_checked += 1
                # The DSL path (left side) is consumed by digDSL — same
                # parsing rules apply minus the bracket support (the DSL
                # values themselves can't address list indices today).
                if "[" in dsl_path or "]" in dsl_path:
                    failures.append(
                        f"{chart_name} v{vidx}: dsl path "
                        f"{dsl_path!r} contains brackets — left side "
                        "of values_mapping doesn't support bracket notation"
                    )
                err = validate_path(dsl_path)
                if err:
                    failures.append(
                        f"{chart_name} v{vidx} dsl_path: {err}"
                    )
                # The target path (right side) is consumed by setAtPath
                # — full bracket-notation contract.
                err = validate_path(target_path)
                if err:
                    failures.append(
                        f"{chart_name} v{vidx} target_path "
                        f"({dsl_path}): {err}"
                    )

            # Also validate binding_secret entries' template fields.
            for bs in version.get("binding_secret") or []:
                tpl = bs.get("template")
                if tpl:
                    # Template values are Helm templates ({{ .Release.Name
                    # }}-...). We don't validate those structurally beyond
                    # checking they're non-empty strings.
                    if not isinstance(tpl, str):
                        failures.append(
                            f"{chart_name} v{vidx} binding_secret[{bs.get('key')}]: "
                            f"template should be a string, got {type(tpl).__name__}"
                        )

    if failures:
        sys.stderr.write(
            "FAIL: dsl-mappings.yaml has invalid values_mapping target path(s).\n"
            "These would silently fail at `rda render` time — the projection "
            "skips the field, helm sees no value, runtime fails without a "
            "clear pointer back to the mapping. See SPEC.md "
            "BEHAVIOR/dsl-mappings-target-validity.\n\n"
        )
        for line in failures:
            sys.stderr.write(f"  {line}\n")
        sys.stderr.write(
            "\nFix: paths use `.` to separate map keys, `name[N]` for list "
            "indices (N is non-negative integer). No empty segments, no "
            "trailing/leading dots, no non-numeric bracket indices.\n"
        )
        return 1

    print(
        f"OK: {paths_checked} values_mapping target path(s) across "
        f"{len(charts)} chart(s) parse cleanly"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
