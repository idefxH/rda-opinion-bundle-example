#!/usr/bin/env bash
# helm-template-smoke — render every chart with realistic values via helm template.
#
# For each chart type in the catalogue, generates a values.yaml with
# the chart enabled + scaffold defaults filled, runs helm template,
# and verifies it produces resources without errors.
#
# For charts with dependencies (dex→postgresql, dex→mariadb,
# airflow→postgresql+redis, etc.), also tests with deps wired.
#
# Requires: helm, python3, PyYAML.
# Runtime: ~30s (no network — uses vendored sub-charts).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$SCRIPT_DIR/../.."

python3 "$SCRIPT_DIR/check.py" "$LIB"
exit $?
