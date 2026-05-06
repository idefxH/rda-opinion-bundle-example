#!/usr/bin/env bash
# Run the binding-secret schema guard. Mirrors the other tests/
# subdirectory pattern so a single `bash tests/*/run.sh` loop covers
# every check.
#
# Usage: ./run.sh
# Requires: python3 + PyYAML.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
python3 "$SCRIPT_DIR/check.py"
exit $?
