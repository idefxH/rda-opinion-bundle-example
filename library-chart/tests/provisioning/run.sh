#!/usr/bin/env bash
# Test runner for the provisioning: deploy|shared|external DSL field.
# Strategy: copy library-chart to a tmpdir, strip the SUSE Application
# Collection dependencies from Chart.yaml so 'helm template' doesn't need
# them vendored, then run each fixture and assert the expected outcome.
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

run_one() {
    local fixture="$1"
    local expect="$2"        # 'fail' or 'pass'
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
        echo "--- output ---"; echo "$out" | head -8; echo "--- end ---"
        FAIL=$((FAIL+1)); return
    fi

    if [[ -n "$must_contain" ]] && ! grep -qF "$must_contain" <<<"$out"; then
        echo "✗ $name: output missing required substring \"$must_contain\""
        echo "--- output ---"; echo "$out" | head -8; echo "--- end ---"
        FAIL=$((FAIL+1)); return
    fi

    echo "✓ $name"
    PASS=$((PASS+1))
}

run_one "$SCRIPT_DIR/01-local-default-postgresql.values.yaml"       pass "host: \"testrelease-postgresql.default.svc.cluster.local\""
run_one "$SCRIPT_DIR/02-shared-with-overlay-defaults-vault.values.yaml"  pass "host: \"shared-pg.platform-services\""
run_one "$SCRIPT_DIR/03-shared-without-overlay-fails.values.yaml"   fail "no defaults.shared_services.postgresql.host"
run_one "$SCRIPT_DIR/04-external-with-endpoint.values.yaml"         pass "host: \"legacy-postgres.corp.local\""
run_one "$SCRIPT_DIR/05-external-missing-endpoint-fails.values.yaml"  fail "no defaults.shared_services"
run_one "$SCRIPT_DIR/06-bad-provisioning-value-fails.values.yaml"   fail "must be 'deploy', 'connect', 'local', 'shared', or 'external'"
run_one "$SCRIPT_DIR/07-grafana-shared-uses-overlay-scheme.values.yaml"  pass "https://grafana.platform-services:3000"
run_one "$SCRIPT_DIR/08-passthrough-on-shared-is-skipped.values.yaml"   pass "host: \"pg.platform-services\""
run_one "$SCRIPT_DIR/09-shared-cross-namespace-fqdn.values.yaml"        pass "host: \"shared-pg-platform-services.platform-services.svc.cluster.local\""

echo ""
echo "Results: $PASS passed, $FAIL failed"
exit $FAIL
