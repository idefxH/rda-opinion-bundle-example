#!/usr/bin/env bash
# Runner for template-procfile-package-consistency.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
python3 "$SCRIPT_DIR/check.py"
exit $?
