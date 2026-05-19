#!/usr/bin/env bash
# Guard: every operator_managed chart type must enable its operator
# sub-chart via chart_defaults, AND must not enable an unrelated
# database sub-chart (the classic "wrong sub-chart" regression: type
# cnpg accidentally setting postgresql.enabled: true instead of
# cloudnative-pg.enabled: true → operator + CRDs never deployed,
# Cluster CR fails to apply).
#
# See check.py for the rationale and the chart-by-chart contract.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
python3 "$SCRIPT_DIR/check.py"
exit $?
