#!/usr/bin/env bash
# Test runner for template-nodejs-package-lock-present.
#
# Asserts that every templates/*/package.json declaring runtime
# dependencies ships a matching package-lock.json so the heroku/nodejs
# buildpack's `npm ci` step doesn't silently skip dep install (or
# fail outright on v5+) and pods don't crash with `Cannot find module`.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
python3 "$SCRIPT_DIR/check.py"
exit $?
