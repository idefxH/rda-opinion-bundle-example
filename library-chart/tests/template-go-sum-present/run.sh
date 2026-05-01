#!/usr/bin/env bash
# Test runner for template-go-sum-present.
#
# Asserts that every templates/*/go.mod with a `require` block ships a
# matching go.sum so the heroku/go buildpack's strict module-aware
# `go install` step doesn't fail at first `tilt up`.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
python3 "$SCRIPT_DIR/check.py"
exit $?
