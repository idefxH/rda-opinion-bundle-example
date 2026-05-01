#!/usr/bin/env python3
"""Assert that every Go template directory with a `go.mod` containing a
`require` block also ships a `go.sum`.

Why this test exists: shipped without a go.sum, the heroku/go buildpack
that `suse_app(language='go')` invokes runs `go install -tags heroku`
in module-aware strict mode. That fails with:

    main.go:N:M: missing go.sum entry for module providing package <pkg>
                  (imported by example.com/<scaffold>); to add:
                  go get example.com/<scaffold>

The error surfaces only at `tilt up` time on a freshly-scaffolded
project — after rda new, after pack build's first stage downloads,
deep inside the buildpack's Go install step. By then the dev has
already lost minutes pulling the heroku/builder:24 image. Catching
this at bundle-PR time is dramatically cheaper.

Discovered live (this commit): web-go template shipped go.mod with a
require block but no go.sum. Every freshly-scaffolded project hit
the buildpack error. Now caught at bundle test time.

Test guard: walks templates/*/go.mod, parses for a `require` line,
and if found asserts go.sum exists in the same directory.

Note: go.sum is deps-deterministic — its content is keyed by module
versions, not the parent's module name. So the same checked-in
go.sum works regardless of `module example.com/{{ .Name }}`
substitution at scaffold time. Devs MAY drop go.sum and re-run
`go mod tidy` to refresh — but it must be present in the template
itself.
"""
import os
import re
import sys


REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TEMPLATES_DIR = os.path.join(REPO_ROOT, "..", "templates")


def go_templates_with_require():
    """Yield (template_dir, go_mod_path) for every template that has a
    go.mod containing a `require` directive."""
    if not os.path.isdir(TEMPLATES_DIR):
        return
    for entry in sorted(os.listdir(TEMPLATES_DIR)):
        tdir = os.path.join(TEMPLATES_DIR, entry)
        if not os.path.isdir(tdir):
            continue
        gomod = os.path.join(tdir, "go.mod")
        if not os.path.isfile(gomod):
            continue
        with open(gomod) as f:
            content = f.read()
        # Detect either a multi-line `require ( ... )` block or a
        # one-line `require <module> <version>` directive. Both forms
        # require a go.sum entry.
        if re.search(r"^\s*require\s+(\(|\S+\s+\S)", content, re.MULTILINE):
            yield entry, gomod


def main():
    drift = []
    inspected = 0
    for name, gomod in go_templates_with_require():
        inspected += 1
        gosum = os.path.join(os.path.dirname(gomod), "go.sum")
        if not os.path.isfile(gosum):
            drift.append((name, gomod, gosum))
            continue
        # Sanity: go.sum non-empty when go.mod has require.
        if os.path.getsize(gosum) == 0:
            drift.append((name, gomod, gosum + " (empty)"))

    if drift:
        print("✗ template-go-sum-present: drift detected", file=sys.stderr)
        print("", file=sys.stderr)
        for name, gomod, gosum in drift:
            print(
                "  - template %s: %s declares require(s) but go.sum missing/empty"
                % (name, os.path.relpath(gomod, REPO_ROOT)),
                file=sys.stderr,
            )
        print("", file=sys.stderr)
        print(
            "  Fix: cd templates/%s && go mod tidy && git add go.sum"
            % drift[0][0],
            file=sys.stderr,
        )
        return 1

    if inspected == 0:
        print("✓ template-go-sum-present: no go.mod with require block found "
              "(no templates need go.sum)")
    else:
        print("✓ template-go-sum-present: %d Go template(s) ship go.sum"
              % inspected)
    return 0


if __name__ == "__main__":
    sys.exit(main())
