#!/usr/bin/env bash
# Smoke tests for the prometheus catalog entry:
#   1. binding-secret has host/port/url with the right values
#   2. NO auth-seed annotation (no auth_seed_paths in dsl-mappings)
#   3. env vars on app Deployment: PROM_HOST/PORT/URL
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
F="$SCRIPT_DIR/01-prometheus-basic.values.yaml"

OUT="$(helm template demo "$CHART" -f "$F" 2>&1)"
RC=$?
if [ $RC -ne 0 ]; then
    echo "✗ helm template failed:"
    echo "$OUT"
    exit 1
fi

PASS=0
FAIL=0
check() {
    local name="$1"
    local needle="$2"
    if echo "$OUT" | grep -q -F "$needle"; then
        echo "✓ $name"
        PASS=$((PASS + 1))
    else
        echo "✗ $name (missing: $needle)"
        FAIL=$((FAIL + 1))
    fi
}

check "binding-secret name = demo-prom-binding" "name: demo-prom-binding"
# Library 0.11.12+: service.host is FQDN (NS Phase C — supports cross-
# namespace shared bindings). helm template's default namespace is
# 'default' when --namespace isn't passed, so the rendered FQDN is
# <release>-<chart>.default.svc.cluster.local.
check "binding-secret host = demo-prometheus-server FQDN" 'host: "demo-prometheus-server.default.svc.cluster.local"'
check "binding-secret port = 80" 'port: "80"'
check "binding-secret url = http://...:80 FQDN" 'url: "http://demo-prometheus-server.default.svc.cluster.local:80"'
check "binding-secret type = prometheus" 'type: "prometheus"'
check "env var PROM_HOST" "name: PROM_HOST"
check "env var PROM_PORT" "name: PROM_PORT"
check "env var PROM_URL" "name: PROM_URL"

# NO auth-seed annotation (stateless type).
if echo "$OUT" | grep -q "rda.suse.com/auth-seed"; then
    # Could match other bindings. Check it's not on the prom binding.
    SEED_LINES="$(echo "$OUT" | awk '/name: demo-prom-binding/,/---/' | grep "auth-seed" || true)"
    if [ -n "$SEED_LINES" ]; then
        echo "✗ prometheus binding-secret should NOT have auth-seed annotation (stateless type)"
        FAIL=$((FAIL + 1))
    else
        echo "✓ prometheus binding-secret correctly omits auth-seed annotation"
        PASS=$((PASS + 1))
    fi
else
    echo "✓ no auth-seed annotation anywhere (correct for stateless prom-only project)"
    PASS=$((PASS + 1))
fi

# NO password env var (prometheus has no auth).
if echo "$OUT" | grep -q "name: PROM_PASSWORD"; then
    echo "✗ prometheus should NOT emit a PROM_PASSWORD env var (no auth)"
    FAIL=$((FAIL + 1))
else
    echo "✓ no PROM_PASSWORD env var (correct for no-auth chart)"
    PASS=$((PASS + 1))
fi

echo
echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
