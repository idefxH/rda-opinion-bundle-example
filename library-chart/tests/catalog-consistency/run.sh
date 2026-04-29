#!/usr/bin/env bash
# Run the cross-repo CATALOG.md ↔ dsl-mappings.yaml consistency check.
# Mirrors the other tests/ subdirectory pattern so a single
# `bash tests/*/run.sh` loop covers every check.
#
# Usage: ./run.sh
# Requires: python3 + PyYAML.
#
# Environment:
#   CATALOG_MD_PATH — explicit path to rda-devx-catalog/CATALOG.md.
#                     Defaults to ../rda-devx-catalog/CATALOG.md
#                     relative to this bundle's repo root (the
#                     conventional sibling-clone layout).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
python3 "$SCRIPT_DIR/check.py"
exit $?
