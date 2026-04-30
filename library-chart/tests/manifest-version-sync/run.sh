#!/usr/bin/env bash
# Assert that library-chart/Chart.yaml's `version` matches
# rda-bundle.yaml's `library_chart.version`. They MUST be equal — `rda
# upgrade` reads the manifest, not the chart, so drift makes it silently
# lie. See check.py for the long-form rationale.
#
# Usage: ./run.sh
# Requires: python3 + PyYAML.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
python3 "$SCRIPT_DIR/check.py"
exit $?
