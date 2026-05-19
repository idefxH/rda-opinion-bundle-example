#!/usr/bin/env bash
# Bump the library-chart version in lockstep across every file that
# pins it. The four locations below MUST stay aligned — drift between
# any pair has shipped real bugs (see CONTRIBUTING.md and
# library-chart/SPEC.md LESSONS):
#
#   1. library-chart/Chart.yaml         — canonical version
#   2. rda-bundle.yaml                  — library_chart.version
#                                          (read by `rda upgrade`)
#   3. templates/*/deploy/Chart.yaml    — chart version
#   4. templates/*/deploy/Chart.yaml    — suse-library dep pin
#                                          (vendored by fresh `rda new`)
#
# Usage:
#   scripts/bump-version.sh <new-version>
#
# Example:
#   scripts/bump-version.sh 0.16.2
#
# After running, verify with:
#   bash library-chart/tests/manifest-version-sync/run.sh
#   bash library-chart/tests/template-version-sync/run.sh
#
# This script does NOT add a MILESTONE block in library-chart/SPEC.md
# nor update META.Version there — those are intentional human steps
# (see CONTRIBUTING.md "Pre-PR checklist") because the milestone needs
# a what/why narrative the script can't write for you.
#
# Behavior on drift: the script aligns every pinned line to <new-version>
# REGARDLESS of its current value. So if templates are stuck at the old
# version while library-chart already moved on, running this with the
# canonical version recovers the aligned state. Idempotent.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: scripts/bump-version.sh <new-version>

Bumps the library-chart version everywhere it's pinned:
  - library-chart/Chart.yaml          (top-level version)
  - rda-bundle.yaml                   (library_chart.version)
  - templates/*/deploy/Chart.yaml     (chart version + suse-library dep)

<new-version> must be a 3-part semver (X.Y.Z).
EOF
  exit 64
}

if [ $# -ne 1 ]; then usage; fi
NEW="$1"
if ! printf '%s' "$NEW" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  printf 'ERROR: "%s" is not a valid semver (expected X.Y.Z)\n' "$NEW" >&2
  exit 1
fi

# Resolve bundle root (parent of scripts/).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUNDLE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$BUNDLE_ROOT"

# Read the current canonical version from library-chart/Chart.yaml
# just for the log line. The replacements below don't depend on it.
OLD="$(python3 -c \
  'import yaml; \
print(yaml.safe_load(open("library-chart/Chart.yaml"))["version"])' \
)"

echo "Bumping library-chart: ${OLD:-?} -> ${NEW}"

# In-place substitution that works on both BSD (macOS) and GNU sed.
# BSD sed requires an explicit suffix after -i; GNU sed accepts that
# too. We pass `.bak` and delete the backup afterward.
inplace_sed() {
  local expr="$1"; shift
  local f
  for f in "$@"; do
    sed -i.bak -E "$expr" "$f"
    rm -f "$f.bak"
  done
}

# Match shape, not specific old value. SEMVER matches X.Y.Z with
# optional pre-release/build suffix (e.g. 0.16.0-rc.1, 1.0.0+build.5).
SEMVER='[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?'

# 1) library-chart/Chart.yaml — top-level `version: X.Y.Z` (unquoted).
#    There's exactly one such line in this file.
inplace_sed "s|^version: ${SEMVER}\$|version: ${NEW}|" \
  library-chart/Chart.yaml

# 2) rda-bundle.yaml — `  version: X.Y.Z` indented exactly two spaces
#    under `library_chart:`. The anchored two-space indent prevents
#    matching some unrelated future `version:` field at a different
#    indent level.
inplace_sed "s|^(  version: )${SEMVER}\$|\\1${NEW}|" \
  rda-bundle.yaml

# 3 + 4) Each templates/*/deploy/Chart.yaml — both the top-level
#    chart version (quoted) and the suse-library dependency pin
#    (indented, unquoted).
for f in templates/*/deploy/Chart.yaml; do
  inplace_sed "s|^version: \"${SEMVER}\"\$|version: \"${NEW}\"|" "$f"
  # Dep pin: indented `version: X.Y.Z`. Each template only has one
  # suse-library dep — and that's the only indented version line in
  # these files — so matching the shape is sufficient. If a template
  # later adds a second dep, this will need a more targeted pattern.
  inplace_sed "s|^([[:space:]]+version: )${SEMVER}\$|\\1${NEW}|" "$f"
done

echo "Done. Verify with:"
echo "  bash library-chart/tests/manifest-version-sync/run.sh"
echo "  bash library-chart/tests/template-version-sync/run.sh"
