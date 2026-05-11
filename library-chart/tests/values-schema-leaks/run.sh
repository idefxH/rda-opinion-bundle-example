#!/usr/bin/env bash
# Assert that library-chart/values.yaml default keys for each sub-chart
# are valid per that sub-chart's actual values schema.
#
# Catches the class of bug where a library default like
# `postgresql.persistence.size: 1Gi` leaks through to the sub-chart's
# template — the chart expects `persistence.resources.requests.storage`,
# not `persistence.size`, and the render.values helper dumps everything,
# producing an invalid StatefulSet.
#
# Approach: for each enabled sub-chart, render with library defaults
# and grep for known invalid field patterns in the rendered YAML.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
python3 "$SCRIPT_DIR/check.py"
exit $?
