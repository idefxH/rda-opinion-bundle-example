#!/usr/bin/env bash
# branch-version-validity — verify every branch points to a real AppCo chart.
#
# For each chart with branches, validates that:
# 1. The chart_version exists in the AppCo OCI registry
# 2. The appVersion matches the expected branch (e.g. branch "17" → PG 17.x)
# 3. The latest available version per branch is used (warns if not)
#
# Requires: crane (go install github.com/google/go-containerregistry/cmd/crane@latest)
# Runtime: ~30s (OCI tag listing + helm show chart per branch)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
python3 "$SCRIPT_DIR/check.py" "$SCRIPT_DIR/../.."
exit $?
