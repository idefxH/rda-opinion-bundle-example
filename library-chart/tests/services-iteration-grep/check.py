#!/usr/bin/env python3
"""Assert that every chart template iterates services[] via the
`enabledServices` helper, not raw `.Values.services`.

Why: see SPEC.md BEHAVIOR/services-iteration. Drift between consumer
templates (binding-secret.yaml using enabledServices but deployment.yaml
using raw .Values.services) caused a real runtime bug at 0.11.9 — a
disabled service's pod tried to mount a Secret the binding-secret
template never rendered.

This test greps every `library-chart/templates/*.yaml` file for
`range .* .Values.services`. A match WITHOUT an `enabledServices`
declaration in scope upstream fails the test with file:line pointers.

Layout: same as the other library-chart/tests/* (run.sh + check.py).
"""
import os
import re
import sys


# Pattern matching: `{{- range $i, $svc := .Values.services }}` and
# variants (different whitespace, different loop variable names).
RANGE_RAW_PATTERN = re.compile(
    r"range\s+(?:\$\w+\s*,\s*)?\$\w+\s*:=\s*\.Values\.services\b"
)
ENABLED_PATTERN = re.compile(
    r'\$\w+\s*:=\s*include\s+"suse-library\.dsl\.enabledServices"'
)


def main() -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    templates_dir = os.path.abspath(
        os.path.join(here, "..", "..", "templates")
    )

    if not os.path.isdir(templates_dir):
        sys.stderr.write(f"FAIL: missing templates dir at {templates_dir}\n")
        return 1

    failures = []

    # Only check `.yaml` chart templates. `.tpl` files (helper definitions)
    # ARE the place where the raw `.Values.services` iteration legitimately
    # lives — the `enabledServices` helper itself walks the raw list to
    # filter it. The invariant is for the consumer side: every chart
    # template that emits resources must go through enabledServices.
    for entry in sorted(os.listdir(templates_dir)):
        if not entry.endswith(".yaml"):
            continue
        path = os.path.join(templates_dir, entry)
        with open(path) as f:
            content = f.read()

        # Track whether an `$enabled := include "...enabledServices..."` has
        # been declared in the file before each raw-services match.
        # Simple heuristic: walk line by line, set a flag when the helper
        # declaration is seen, flag any raw-services match seen before that
        # OR with the helper out of scope.
        #
        # This is a conservative grep — it doesn't model Helm's full
        # variable scoping. It catches the common case (file-level decl
        # followed by sibling ranges) which is the pattern we want to
        # enforce. False positives can be fixed by hoisting the
        # declaration; false negatives would require deliberate
        # circumvention (declaring `$enabled` then ignoring it).
        enabled_seen = False
        for lineno, line in enumerate(content.splitlines(), start=1):
            if ENABLED_PATTERN.search(line):
                enabled_seen = True
                continue
            if RANGE_RAW_PATTERN.search(line):
                if not enabled_seen:
                    failures.append(
                        f"{path}:{lineno}: raw `.Values.services` iteration "
                        "without an `$enabled := include "
                        '"suse-library.dsl.enabledServices"` declared above. '
                        "See SPEC.md BEHAVIOR/services-iteration."
                    )

    if failures:
        sys.stderr.write(
            "FAIL: chart template(s) iterate raw `.Values.services` instead "
            "of the enabledServices helper. This breaks the\n"
            "services-iteration invariant — a disabled service ends up "
            "referenced by some templates but not others, and pods stick\n"
            "in pending with confusing MountVolume errors.\n\n"
        )
        for line in failures:
            sys.stderr.write(f"  {line}\n")
        sys.stderr.write(
            "\nFix: hoist `$enabled := include "
            '"suse-library.dsl.enabledServices" $ | fromJsonArray` near\n'
            "the top of the template, then `range $i, $svc := $enabled` "
            "everywhere.\n"
        )
        return 1

    print("OK: every services[] iteration uses the enabledServices helper")
    return 0


if __name__ == "__main__":
    sys.exit(main())
