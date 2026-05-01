#!/usr/bin/env python3
"""Assert that every Go template's `go.mod` directive is high enough
to satisfy the `go` directive of every dep listed in `require`.

Why this test exists: PR #100 shipped go.mod with `go 1.22` AND
`require github.com/jackc/pgx/v5 v5.7.6`. pgx v5.7.0+ requires
go 1.23, so the heroku/go buildpack's `go list -tags heroku` fails:

    go: github.com/jackc/pgx/v5@v5.7.6 requires go >= 1.23.0
        (running go 1.22.12)

The buildpack picks the Go toolchain to install based on the go.mod
directive. If a dep needs newer Go than the directive declares,
build crashes — visible only at first `tilt up`, after pack pulls
heroku/builder:24. We catch this at bundle PR review by reading
each dep's published go.mod via `go env -json` is too heavy for a
test guard, so we hardcode known minimum-version requirements per
dep that has bitten us. Update when a new dep version raises its
floor.

The dep_floors table is the authoritative knowledge: each entry says
'when you require github.com/X/Y at version V or above, your go.mod
must declare go >= go_min'. Update when a dep's floor changes.
"""
import os
import re
import sys
from functools import cmp_to_key


REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TEMPLATES_DIR = os.path.join(REPO_ROOT, "..", "templates")

# (module, min_version_pulling_floor, required_go_minor)
# Read: when go.mod requires <module> at >= min_version, the go
# directive must be >= 1.<required_go_minor>.
DEP_FLOORS = [
    ("github.com/jackc/pgx/v5", (5, 7, 0), 23),
    # Add more as new deps surface go-floor mismatches:
    # ("github.com/foo/bar", (1, 2, 3), 22),
]


def parse_semver(s):
    """vX.Y.Z → (X, Y, Z). Tolerates 'v' prefix and pre-release suffix."""
    s = s.lstrip("v")
    s = s.split("-", 1)[0]  # drop pre-release
    parts = s.split(".")
    while len(parts) < 3:
        parts.append("0")
    return tuple(int(p) for p in parts[:3])


def parse_go_directive(content):
    """Returns minor int from `go 1.X` line, or None if missing."""
    m = re.search(r"^go\s+1\.(\d+)", content, re.MULTILINE)
    if m:
        return int(m.group(1))
    return None


def parse_requires(content):
    """Returns dict {module: parsed_semver_tuple} from a go.mod string.

    Supports both block form `require ( module v1.2.3 )` and single-
    line form `require module v1.2.3`."""
    out = {}
    # Multi-line block.
    block = re.search(r"^require\s*\(\s*\n(.*?)\n\)", content, re.MULTILINE | re.DOTALL)
    body = block.group(1) if block else ""
    # Single-line directives: `require module v1.2.3`.
    for line in re.findall(r"^require\s+(\S+)\s+(\S+)\s*$", content, re.MULTILINE):
        out[line[0]] = parse_semver(line[1])
    # Lines inside the block.
    for line in body.split("\n"):
        line = line.strip()
        if not line or line.startswith("//"):
            continue
        toks = line.split()
        if len(toks) >= 2:
            out[toks[0]] = parse_semver(toks[1])
    return out


def main():
    drift = []
    inspected = 0
    if not os.path.isdir(TEMPLATES_DIR):
        return 0

    for entry in sorted(os.listdir(TEMPLATES_DIR)):
        tdir = os.path.join(TEMPLATES_DIR, entry)
        gomod = os.path.join(tdir, "go.mod")
        if not os.path.isfile(gomod):
            continue
        inspected += 1
        with open(gomod) as f:
            content = f.read()
        go_minor = parse_go_directive(content)
        requires = parse_requires(content)

        for mod, min_floor_ver, required_go in DEP_FLOORS:
            if mod not in requires:
                continue
            if requires[mod] >= min_floor_ver:
                if go_minor is None or go_minor < required_go:
                    drift.append(
                        (entry, mod, requires[mod], required_go, go_minor)
                    )

    if drift:
        print("✗ template-go-deps-version-compat: drift detected", file=sys.stderr)
        print("", file=sys.stderr)
        for tmpl, mod, ver, need_go, have_go in drift:
            ver_s = ".".join(str(x) for x in ver)
            print(
                "  - template %s requires %s v%s which needs go >= 1.%d, "
                "but go.mod declares go 1.%s"
                % (tmpl, mod, ver_s, need_go, str(have_go) if have_go is not None else "?"),
                file=sys.stderr,
            )
        print("", file=sys.stderr)
        print("  Fix: bump the `go 1.X` directive in templates/<name>/go.mod.", file=sys.stderr)
        return 1

    if inspected == 0:
        print("✓ template-go-deps-version-compat: no Go template found")
    else:
        print("✓ template-go-deps-version-compat: %d Go template(s) "
              "have go directive >= each dep's published floor" % inspected)
    return 0


if __name__ == "__main__":
    sys.exit(main())
