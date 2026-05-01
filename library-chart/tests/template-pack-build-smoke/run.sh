#!/usr/bin/env bash
# Runner for template-pack-build-smoke.
#
# Actually invokes `pack build` on each rendered template — catches
# real buildpack regressions (go.sum missing, Procfile-vs-package
# drift, go-vs-dep version floors, etc.) at bundle PR time instead
# of at the dev's first `tilt up`.
#
# Soft-skips when pack CLI / docker daemon / network are missing.
# Set SKIP_PACK_SMOKE=1 to opt out explicitly (e.g. fast inner loop).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
python3 "$SCRIPT_DIR/check.py"
exit $?
