#!/usr/bin/env bash
# Test runner for the DSL ↔ passthrough collision detection helper.
# Strategy: copy library-chart to a tmpdir, strip the AppCo dependencies
# from Chart.yaml so 'helm template' doesn't need them vendored, then
# run each fixture and assert the expected outcome.
#
# Each fixture's expected outcome is encoded in the filename prefix:
#   '0[126]-collision-*' / '0[5]-multi-service-second-collides-*' must FAIL
#   '0[34]-no-collision-*' must SUCCEED.
# Failure cases also assert the binding name appears in the error.
#
# Usage: ./run.sh
# Expects helm on PATH.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHART_SRC="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Copy chart and strip dependencies (we don't have AppCo creds in CI).
cp -r "$CHART_SRC" "$WORK/library-chart"
python3 -c "
import re, sys
p = '$WORK/library-chart/Chart.yaml'
s = open(p).read()
s = re.sub(r'\ndependencies:.*', '\n', s, flags=re.DOTALL)
open(p, 'w').write(s)
"

CHART="$WORK/library-chart"
PASS=0
FAIL=0

run_one() {
    local fixture="$1"
    local expect="$2"
    local must_contain="${3:-}"
    local name="$(basename "$fixture")"

    local out
    if out=$(helm template testrelease "$CHART" --values "$fixture" 2>&1); then
        local got=pass
    else
        local got=fail
    fi

    if [[ "$got" != "$expect" ]]; then
        echo "✗ $name: expected $expect, got $got"
        echo "--- output ---"
        echo "$out" | head -8
        echo "--- end ---"
        FAIL=$((FAIL+1))
        return
    fi

    if [[ -n "$must_contain" ]] && ! grep -qF "$must_contain" <<<"$out"; then
        echo "✗ $name: output missing required substring \"$must_contain\""
        echo "--- output ---"
        echo "$out" | head -8
        echo "--- end ---"
        FAIL=$((FAIL+1))
        return
    fi

    echo "✓ $name"
    PASS=$((PASS+1))
}

run_one "$SCRIPT_DIR/01-collision-persistence-enabled.values.yaml" fail "binding=database"
run_one "$SCRIPT_DIR/02-collision-mapped-path.values.yaml"          fail "binding=database"
run_one "$SCRIPT_DIR/03-no-collision-different-paths.values.yaml"   pass
run_one "$SCRIPT_DIR/04-no-collision-deeper-passthrough.values.yaml" pass
run_one "$SCRIPT_DIR/05-multi-service-second-collides.values.yaml"  fail "binding=database"
run_one "$SCRIPT_DIR/06-redis-collision-master-prefix.values.yaml"  fail "binding=cache"

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $FAIL
