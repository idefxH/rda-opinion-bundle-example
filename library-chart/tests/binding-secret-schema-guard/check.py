#!/usr/bin/env python3
"""
Validate binding_secret cross-references against values_mapping and scaffold.

For each chart type in dsl-mappings.yaml, verify:
  1. Every binding_secret[].key with `from_dsl:` has a corresponding path
     in values_mapping OR scaffold (the from_dsl value must resolve to a
     known DSL path the render pipeline can wire).
  2. Every binding_secret[].key with `required: true` has a scaffold entry
     with a non-empty comment (so the developer gets guidance on what the
     field is for when they scaffold the service).

This catches silent wiring gaps BEFORE they surface as empty binding-secret
values at deploy time. Designed to run in CI and in `library-chart/tests/`.

Exit codes:
  0  all cross-references valid
  1  mismatches found (errors printed to stderr)
"""
import os
import sys

try:
    import yaml
except ImportError:
    sys.stderr.write("PyYAML not installed; pip3 install pyyaml or use python3 -m pip install pyyaml\n")
    sys.exit(2)

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MAPPING_FILE = os.path.join(REPO_ROOT, "dsl-mappings.yaml")


def err(errors, path, msg):
    errors.append("%s: %s" % (path, msg))


def check_chart(errors, chart, body):
    """Validate binding_secret cross-references for one chart."""
    versions = body.get("versions")
    if not isinstance(versions, list):
        return

    for vidx, ver in enumerate(versions):
        if not isinstance(ver, dict):
            continue

        base = "charts.%s.versions[%d]" % (chart, vidx)
        bs = ver.get("binding_secret")
        vm = ver.get("values_mapping") or {}
        scaffold = ver.get("scaffold") or {}

        if not isinstance(bs, list):
            continue

        vm_dsl_paths = set(vm.keys()) if isinstance(vm, dict) else set()
        scaffold_keys = set(scaffold.keys()) if isinstance(scaffold, dict) else set()

        for ei, entry in enumerate(bs):
            if not isinstance(entry, dict):
                continue
            key = entry.get("key", "<unknown>")
            path = "%s.binding_secret[%d].key=%s" % (base, ei, key)

            # ── Check 1: from_dsl path must be resolvable ──
            from_dsl = entry.get("from_dsl")
            if from_dsl is not None:
                if not isinstance(from_dsl, str) or not from_dsl:
                    err(errors, path,
                        "from_dsl must be a non-empty string, got %r" % from_dsl)
                    continue

                # The from_dsl value should exist as a key in values_mapping
                # (the render pipeline reads it from the service DSL entry
                # and writes it to the chart's values) OR in scaffold (the
                # scaffold formatter generates the field for the developer).
                # If it's in neither, the binding-secret key will always
                # resolve to empty at deploy time.
                if from_dsl not in vm_dsl_paths and from_dsl not in scaffold_keys:
                    err(errors, path,
                        "from_dsl=%r is not in values_mapping keys %s "
                        "and not in scaffold keys %s — the binding-secret "
                        "key will resolve to empty at deploy time" % (
                            from_dsl,
                            sorted(vm_dsl_paths),
                            sorted(scaffold_keys)))

            # ── Check 2: required + from_dsl => scaffold with comment ──
            if entry.get("required") is True and from_dsl is not None:
                # A required from_dsl field MUST have a scaffold entry with
                # a comment so the developer knows what to fill in.
                scaffold_entry = scaffold.get(from_dsl)
                if scaffold_entry is None:
                    err(errors, path,
                        "required from_dsl=%r has no scaffold entry — "
                        "the developer won't see this field in the scaffold "
                        "output and won't know they must fill it in" % from_dsl)
                elif isinstance(scaffold_entry, dict):
                    comment = scaffold_entry.get("comment", "")
                    if not comment:
                        err(errors, path,
                            "required from_dsl=%r has a scaffold entry but "
                            "no comment — add a comment so the developer "
                            "knows what the field is for" % from_dsl)


def main():
    if not os.path.isfile(MAPPING_FILE):
        print("ERROR: %s not found" % MAPPING_FILE, file=sys.stderr)
        return 1
    with open(MAPPING_FILE) as f:
        try:
            doc = yaml.safe_load(f)
        except yaml.YAMLError as e:
            print("ERROR: %s: parse error: %s" % (MAPPING_FILE, e), file=sys.stderr)
            return 1

    if not isinstance(doc, dict):
        print("ERROR: root must be a dict", file=sys.stderr)
        return 1

    charts = doc.get("charts")
    if not isinstance(charts, dict) or not charts:
        print("ERROR: charts must be a non-empty dict", file=sys.stderr)
        return 1

    errors = []
    chart_count = 0
    bs_key_count = 0

    for chart, body in charts.items():
        if not isinstance(body, dict):
            continue
        chart_count += 1
        versions = body.get("versions") or []
        for ver in versions:
            if isinstance(ver, dict):
                bs = ver.get("binding_secret") or []
                if isinstance(bs, list):
                    bs_key_count += len([e for e in bs if isinstance(e, dict)])
        check_chart(errors, chart, body)

    if errors:
        print("✗ binding-secret schema guard failed:", file=sys.stderr)
        for e in errors:
            print("  - " + e, file=sys.stderr)
        print("", file=sys.stderr)
        print("%d error(s) across %d chart(s), %d binding_secret keys checked." % (
            len(errors), chart_count, bs_key_count), file=sys.stderr)
        return 1

    print("✓ binding-secret schema guard passed: "
          "%d chart(s), %d binding_secret key(s) — "
          "all from_dsl paths resolvable, all required fields have scaffold comments"
          % (chart_count, bs_key_count))
    return 0


if __name__ == "__main__":
    sys.exit(main())
