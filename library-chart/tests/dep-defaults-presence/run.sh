#!/usr/bin/env bash
# Assert every Chart.yaml dep gates on `<name>.enabled` and has a
# matching default in values.yaml. See check.py for the rationale and
# SPEC.md BEHAVIOR/dep-defaults-presence for the canonical contract.
#
# Usage: ./run.sh
# Requires: python3 + PyYAML.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
python3 "$SCRIPT_DIR/check.py"
exit $?
