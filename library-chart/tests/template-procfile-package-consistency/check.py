#!/usr/bin/env python3
"""Assert that every command in a Node.js template's Procfile is
resolvable at runtime — either a built-in (node, npm, npx, sh, bash)
OR a binary that ships from the package.json's dependencies (and
therefore lands in node_modules/.bin via the buildpack's
z_node_module_bins layer).

Why this test exists: PR #100 dropped `nodemon` from package.json
deps when it switched to node --watch, but left the old Procfile
that called `nodemon -L src/index.js`. The CNB launcher then ran the
'dev' process, which exec'd `nodemon`, which wasn't on PATH:

    bash: line 1: nodemon: command not found
    Back-off restarting failed container app

The pod sat in CrashLoopBackOff. Visible only at runtime; pack build
itself succeeded. Catching this at bundle PR review by parsing both
files and asserting Procfile commands are reachable.

Heuristic: only flag commands that look like a JS-tool name (lowercase
identifier-shaped). Things like `node`, `npm`, `npx`, `sh`, `bash` are
buildpack/runtime built-ins and pass.
"""
import json
import os
import re
import sys


REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TEMPLATES_DIR = os.path.join(REPO_ROOT, "..", "templates")

# Commands resolvable without a node_modules/.bin entry. node-ish
# runtimes + standard shells. Extend if a future template starts using
# something else (e.g. python, go) at Procfile launch — but those are
# language-specific buildpacks and unlikely to share a Procfile.
RUNTIME_BINS = frozenset({
    "node", "npm", "npx", "yarn", "pnpm",
    "sh", "bash", "/bin/sh", "/bin/bash", "/usr/bin/env",
})


def parse_procfile(path):
    """Returns dict {process_name: first_token_of_command}."""
    out = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if ":" not in line:
                continue
            name, cmd = line.split(":", 1)
            tokens = cmd.strip().split()
            if tokens:
                out[name.strip()] = tokens[0]
    return out


def parse_package_deps(path):
    """Returns the union of dependencies + devDependencies keys."""
    with open(path) as f:
        pkg = json.load(f)
    return set((pkg.get("dependencies") or {}).keys()) | \
           set((pkg.get("devDependencies") or {}).keys())


def main():
    drift = []
    inspected = 0
    if not os.path.isdir(TEMPLATES_DIR):
        print("✗ templates/ not found at " + TEMPLATES_DIR, file=sys.stderr)
        return 2

    for entry in sorted(os.listdir(TEMPLATES_DIR)):
        tdir = os.path.join(TEMPLATES_DIR, entry)
        if not os.path.isdir(tdir):
            continue
        procfile = os.path.join(tdir, "Procfile")
        pkg_json = os.path.join(tdir, "package.json")
        if not (os.path.isfile(procfile) and os.path.isfile(pkg_json)):
            continue
        inspected += 1
        commands = parse_procfile(procfile)
        deps = parse_package_deps(pkg_json)
        for proc_name, cmd in commands.items():
            # Skip flags accidentally captured (shouldn't happen with
            # split() but be defensive).
            if cmd.startswith("-"):
                continue
            # Strip leading ./ or path components — we want the base
            # binary name to look up against deps/runtime.
            basename = os.path.basename(cmd)
            if basename in RUNTIME_BINS:
                continue
            # Some Procfiles call package.json scripts via `npm run X`;
            # that's already covered (cmd=npm in RUNTIME_BINS).
            if basename in deps:
                continue
            # Identifier-shaped (lowercase + digits + dash) → it's a
            # JS-tool name. Anything else is probably a path/expression
            # we can't statically validate; skip with no opinion.
            if re.match(r"^[a-z][a-z0-9_-]*$", basename):
                drift.append((entry, proc_name, basename))

    if drift:
        print("✗ template-procfile-package-consistency: drift detected", file=sys.stderr)
        print("", file=sys.stderr)
        for tmpl, proc, cmd in drift:
            print(
                "  - template %s, Procfile process %r: command %r is "
                "neither a runtime built-in nor in package.json deps. "
                "Pod will CrashLoopBackOff with 'command not found'."
                % (tmpl, proc, cmd),
                file=sys.stderr,
            )
        print("", file=sys.stderr)
        print(
            "  Fix: either (a) add %r to package.json dependencies so "
            "node_modules/.bin/%s ships, or (b) replace the Procfile "
            "command with a runtime built-in (node, npm, npx, ...)."
            % (drift[0][2], drift[0][2]),
            file=sys.stderr,
        )
        return 1

    if inspected == 0:
        print("✓ template-procfile-package-consistency: no Node.js template "
              "with both Procfile + package.json found")
    else:
        print("✓ template-procfile-package-consistency: %d template(s) "
              "checked, all Procfile commands resolvable" % inspected)
    return 0


if __name__ == "__main__":
    sys.exit(main())
