#!/usr/bin/env bash
# Test runner for auto-Ingress on catalogued UI services (issue #8).
# Strategy mirrors the passthrough-collision suite: copy the chart to a
# tmpdir, strip dependencies, then assert the rendered Ingress count and
# substrings.
#
# Usage: ./run.sh
# Expects helm on PATH.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHART_SRC="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cp -r "$CHART_SRC" "$WORK/library-chart"
python3 -c "
import re
p = '$WORK/library-chart/Chart.yaml'
s = open(p).read()
s = re.sub(r'\ndependencies:.*', '\n', s, flags=re.DOTALL)
open(p, 'w').write(s)
"

CHART="$WORK/library-chart"
PASS=0
FAIL=0

# Render values.yaml and assert:
# - ingress_count: expected number of `kind: Ingress` in the rendered output
# - must_contain: optional substring (e.g. host name) that must appear
run_one() {
    local fixture="$1"
    local expected_count="$2"
    local must_contain="${3:-}"
    local name="$(basename "$fixture")"

    local out
    out=$(helm template testrel "$CHART" --values "$fixture" 2>&1)
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        echo "✗ $name: helm template failed (rc=$rc)"
        echo "--- output ---"
        echo "$out" | head -12
        echo "--- end ---"
        FAIL=$((FAIL+1))
        return
    fi

    local got_count
    got_count=$(grep -c "^kind: Ingress$" <<<"$out" || true)
    if [[ "$got_count" != "$expected_count" ]]; then
        echo "✗ $name: expected $expected_count Ingress(es), got $got_count"
        echo "$out" | grep -E "^kind: Ingress|^  name:" | head -8
        FAIL=$((FAIL+1))
        return
    fi

    if [[ -n "$must_contain" ]] && ! grep -qF "$must_contain" <<<"$out"; then
        echo "✗ $name: output missing required substring \"$must_contain\""
        echo "$out" | grep -E "host:" | head -4
        FAIL=$((FAIL+1))
        return
    fi

    echo "✓ $name"
    PASS=$((PASS+1))
}

# Both UI charts enabled, default ui.expose=true → 2 UI Ingresses
run_one "$SCRIPT_DIR/01-grafana-and-prometheus-default.values.yaml" 2 "grafana.testrel.localhost"

# grafana only → 1 UI Ingress
run_one "$SCRIPT_DIR/02-grafana-only.values.yaml" 1 "grafana.testrel.localhost"

# prometheus only → 1 UI Ingress, host has -server suffix in service backend
run_one "$SCRIPT_DIR/03-prometheus-only.values.yaml" 1 "prometheus.testrel.localhost"

# expose:false on grafana → 0 UI Ingresses (chart still enabled)
run_one "$SCRIPT_DIR/04-grafana-expose-false.values.yaml" 0

# Custom host via ui.host
run_one "$SCRIPT_DIR/05-custom-host.values.yaml" 1 "metrics.dev.local"

# All charts disabled → 0 UI Ingresses
run_one "$SCRIPT_DIR/06-all-disabled.values.yaml" 0

# Project ingress.enabled=true is unrelated — should still render only the
# project's own Ingress (1) plus 0 UI Ingresses when no UI charts enabled
run_one "$SCRIPT_DIR/07-project-ingress-no-ui.values.yaml" 1 "demo.localhost"

# Project ingress + grafana UI → 2 Ingresses total
run_one "$SCRIPT_DIR/08-project-ingress-plus-grafana.values.yaml" 2 "grafana.testrel.localhost"

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $FAIL
