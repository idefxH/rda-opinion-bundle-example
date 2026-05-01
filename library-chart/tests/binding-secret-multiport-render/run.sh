#!/usr/bin/env bash
# Test runner for binding-secret-multiport-render.
#
# Asserts that helm template against suse-library renders a valid
# binding-secret.yaml when BOTH a single-port (postgresql) and a
# multi-port (dex) binding are enabled. Catches the multi-port
# emission helper's right-trim indentation bug.
#
# Soft-skips when helm CLI / PyYAML are missing (no fixture box
# inflicts a regression on the operator running tests on a fresh
# clone with no helm installed).

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
python3 "$SCRIPT_DIR/check.py"
exit $?
