#!/usr/bin/env python3
"""Assert that every Node.js template directory with a `package.json`
declaring runtime `dependencies` also ships a `package-lock.json`.

Why this test exists: heroku/nodejs buildpack v5+ (the version baked
into heroku/builder:24) installs runtime deps via `npm ci`, which
*requires* a checked-in package-lock.json. Without it, the buildpack
fails (or more subtly, falls back to a path that skips dependency
install entirely on some versions), and the launched container
crashes at runtime with errors like:

    Error: Cannot find module 'pg'
    Require stack:
    - /workspace/src/index.js

This failure is invisible at `pack build` time on some buildpack
versions (the build "succeeds") and only surfaces when the pod tries
to start — by which point the dev has waited through a full pack
build and a Tilt deploy. Catching the missing lock file at bundle-PR
time is dramatically cheaper.

Discovered live (this commit): web-nodejs template shipped a Message
Wall app with `pg` and `prom-client` in package.json's dependencies,
but no package-lock.json. Every freshly-scaffolded Node project
crash-looped on missing modules. Now caught at bundle test time.

Test guard: walks templates/*/package.json. For each template with a
non-empty `dependencies` (or `optionalDependencies`) object, asserts
that package-lock.json exists alongside it and is non-empty.

Note: package-lock.json is keyed by package versions, not by the
parent's `name` field. So the same checked-in lock works regardless
of `"name": "{{ .Name }}"` substitution at scaffold time. Devs MAY
delete it and re-run `npm install --package-lock-only` to refresh —
but it must be present in the template itself.
"""
import json
import os
import sys


REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TEMPLATES_DIR = os.path.join(REPO_ROOT, "..", "templates")


def node_templates_with_deps():
    """Yield (template_name, package_json_path, dep_count) for every
    Node template whose package.json declares runtime dependencies."""
    if not os.path.isdir(TEMPLATES_DIR):
        return
    for entry in sorted(os.listdir(TEMPLATES_DIR)):
        tdir = os.path.join(TEMPLATES_DIR, entry)
        if not os.path.isdir(tdir):
            continue
        pkg = os.path.join(tdir, "package.json")
        if not os.path.isfile(pkg):
            continue
        # package.json may contain Go-template placeholders like
        # `"name": "{{ .Name }}"`. We only care about the deps fields,
        # which are pure JSON, so a tolerant load is fine: read raw
        # then strip the outer `name` line if it'd choke json.loads.
        try:
            with open(pkg) as f:
                raw = f.read()
            data = json.loads(raw)
        except json.JSONDecodeError:
            # Best-effort: replace common Go-template tokens, retry.
            cleaned = raw.replace("{{ .Name }}", "tpl")
            try:
                data = json.loads(cleaned)
            except json.JSONDecodeError:
                # Can't parse — skip rather than false-positive.
                continue
        deps = data.get("dependencies") or {}
        opt = data.get("optionalDependencies") or {}
        total = len(deps) + len(opt)
        if total == 0:
            continue
        yield entry, pkg, total


def main():
    drift = []
    inspected = 0
    for name, pkg, ndeps in node_templates_with_deps():
        inspected += 1
        lock = os.path.join(os.path.dirname(pkg), "package-lock.json")
        if not os.path.isfile(lock):
            drift.append((name, pkg, lock, ndeps, "missing"))
            continue
        if os.path.getsize(lock) == 0:
            drift.append((name, pkg, lock, ndeps, "empty"))

    if drift:
        print("✗ template-nodejs-package-lock-present: drift detected", file=sys.stderr)
        print("", file=sys.stderr)
        for name, pkg, lock, ndeps, why in drift:
            print(f"  {name}: {ndeps} runtime deps in {pkg}", file=sys.stderr)
            print(f"    ↳ package-lock.json {why} at {lock}", file=sys.stderr)
        print("", file=sys.stderr)
        print(
            "heroku/nodejs buildpack v5+ requires package-lock.json for `npm ci`.",
            file=sys.stderr,
        )
        print(
            "Without it, the launched pod crashes at runtime with `Cannot find module`.",
            file=sys.stderr,
        )
        print("", file=sys.stderr)
        print("Fix: from inside the template directory, run:", file=sys.stderr)
        print("    npm install --package-lock-only --no-audit --no-fund", file=sys.stderr)
        print("Then commit the generated package-lock.json.", file=sys.stderr)
        print("", file=sys.stderr)
        print(
            "(If your package.json has `\"name\": \"{{ .Name }}\"`, sed-replace it",
            file=sys.stderr,
        )
        print(
            " to a placeholder before `npm install`, then sed-restore the placeholder.)",
            file=sys.stderr,
        )
        return 1

    print(
        f"✓ template-nodejs-package-lock-present: {inspected} template(s) inspected, "
        "all OK."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
