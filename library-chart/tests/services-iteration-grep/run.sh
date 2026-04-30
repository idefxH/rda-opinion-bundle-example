#!/usr/bin/env bash
# Assert services[] iteration goes through enabledServices in every
# template. See check.py for the long-form rationale and SPEC.md
# BEHAVIOR/services-iteration for the canonical contract.
#
# Usage: ./run.sh
# Requires: python3 (no PyYAML — pure regex grep).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
python3 "$SCRIPT_DIR/check.py"
exit $?
