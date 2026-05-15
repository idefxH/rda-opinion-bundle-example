#!/usr/bin/env bash
# Strip AppCo-only OCI deps from library-chart/Chart.yaml so `helm dep
# update` succeeds without SUSE Application Collection credentials.
# Thin wrapper around library-chart/scripts/chart-source.py.
#
# Use in CI:
#   scripts/use-community-charts.sh
#
# Reverse with:
#   scripts/use-appco-charts.sh   # or: git checkout library-chart/Chart.yaml
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
bundle_root=$(cd -- "$here/.." && pwd)
exec python3 "$bundle_root/library-chart/scripts/chart-source.py" --mode community "$@"
