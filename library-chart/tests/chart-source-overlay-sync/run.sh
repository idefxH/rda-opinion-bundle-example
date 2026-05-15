#!/usr/bin/env bash
# Test runner for chart-source-overlay-sync.
#
# Asserts that library-chart/scripts/appco-overlay.yaml stays in lockstep
# with the AppCo OCI block of library-chart/Chart.yaml. Drift here would
# silently break `scripts/use-appco-charts.sh` (restored deps would have
# the wrong version, repository, or condition).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

python3 "$LIB_DIR/scripts/chart-source.py" --check
exit $?
