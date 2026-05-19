#!/usr/bin/env bash
# Assert that every templates/*/deploy/Chart.yaml pins the same
# library-chart version as library-chart/Chart.yaml — both the chart's
# own `version:` and its `suse-library` dependency. Drift makes fresh
# `rda new` projects scaffold against the wrong library version (the
# bug is invisible at scaffold time and surfaces as a behavior
# regression later). See check.py for the long-form rationale.
#
# Usage: ./run.sh
# Requires: python3 + PyYAML.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
python3 "$SCRIPT_DIR/check.py"
exit $?
