#!/usr/bin/env bash
# Restore the AppCo-only OCI deps in library-chart/Chart.yaml from
# library-chart/scripts/appco-overlay.yaml. Reverse of
# scripts/use-community-charts.sh.
#
# Idempotent — re-running when all AppCo deps are already present
# is a no-op.
set -euo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
bundle_root=$(cd -- "$here/.." && pwd)
exec python3 "$bundle_root/library-chart/scripts/chart-source.py" --mode appco "$@"
