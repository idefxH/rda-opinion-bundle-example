#!/usr/bin/env bash
# Assert every values_mapping target path in dsl-mappings.yaml parses
# under the bracket-notation rules `rda render` enforces. See check.py
# for the rationale and SPEC.md BEHAVIOR/dsl-mappings-target-validity
# for the canonical contract.
#
# Usage: ./run.sh
# Requires: python3 + PyYAML.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
python3 "$SCRIPT_DIR/check.py"
exit $?
