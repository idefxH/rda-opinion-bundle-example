#!/usr/bin/env bash
# Smoke tests for auth-seed annotation (#63):
#   1. postgres-with-auth_seed_paths emits the annotation
#   2. grafana (stateless, no auth_seed_paths) does NOT emit
#   3. shared provisioning does NOT emit (no PVC to drift against)
#
# We don't test the validateConsistency drift check here because it
# depends on Helm's `lookup` returning a non-nil resource, which only
# happens at apply time (not at helm template). The drift check is
# documented in the helper and exercised end-to-end in the demo flow.
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

# 1. postgres emits the annotation
F1="$SCRIPT_DIR/01-postgres-emits-auth-seed.values.yaml"
OUT1="$(helm template demo "$CHART" -f "$F1" 2>&1)"
if echo "$OUT1" | grep -q "rda.suse.com/auth-seed:"; then
    SEED="$(echo "$OUT1" | grep "rda.suse.com/auth-seed:" | head -1 | sed 's/.*"\(.*\)".*/\1/')"
    if [ -z "$SEED" ] || [ "${#SEED}" -ne 16 ]; then
        echo "✗ 01: auth-seed present but value is not a 16-char hash: $SEED"
        FAIL=$((FAIL + 1))
    else
        echo "✓ 01: postgres emits rda.suse.com/auth-seed=$SEED (16-char hash)"
        PASS=$((PASS + 1))
    fi
else
    echo "✗ 01: postgres should emit rda.suse.com/auth-seed annotation"
    echo "$OUT1" | grep -A 2 "annotations:" | head -10
    FAIL=$((FAIL + 1))
fi

# 1b. Same input = same hash (determinism)
OUT1b="$(helm template demo "$CHART" -f "$F1" 2>&1)"
SEED1b="$(echo "$OUT1b" | grep "rda.suse.com/auth-seed:" | head -1 | sed 's/.*"\(.*\)".*/\1/')"
if [ "$SEED" = "$SEED1b" ]; then
    echo "✓ 01b: auth-seed is deterministic across runs ($SEED)"
    PASS=$((PASS + 1))
else
    echo "✗ 01b: auth-seed is non-deterministic: $SEED vs $SEED1b"
    FAIL=$((FAIL + 1))
fi

# 1c. Different password = different hash
TMPVAL="$(mktemp)"
sed 's/app-pw/different-pw/' "$F1" > "$TMPVAL"
OUT1c="$(helm template demo "$CHART" -f "$TMPVAL" 2>&1)"
SEED1c="$(echo "$OUT1c" | grep "rda.suse.com/auth-seed:" | head -1 | sed 's/.*"\(.*\)".*/\1/')"
if [ -n "$SEED1c" ] && [ "$SEED" != "$SEED1c" ]; then
    echo "✓ 01c: auth-seed changes when password changes ($SEED -> $SEED1c)"
    PASS=$((PASS + 1))
else
    echo "✗ 01c: auth-seed should change when password changes (got '$SEED' and '$SEED1c')"
    FAIL=$((FAIL + 1))
fi
rm -f "$TMPVAL"

# 2. grafana (stateless) does NOT emit
F2="$SCRIPT_DIR/02-grafana-no-auth-seed.values.yaml"
OUT2="$(helm template demo "$CHART" -f "$F2" 2>&1)"
if echo "$OUT2" | grep -q "rda.suse.com/auth-seed:"; then
    echo "✗ 02: grafana should NOT emit auth-seed (no auth_seed_paths in dsl-mappings)"
    FAIL=$((FAIL + 1))
else
    echo "✓ 02: grafana correctly skips auth-seed annotation"
    PASS=$((PASS + 1))
fi

# 3. shared provisioning does NOT emit
F3="$SCRIPT_DIR/03-shared-no-auth-seed.values.yaml"
OUT3="$(helm template demo "$CHART" -f "$F3" 2>&1)"
if echo "$OUT3" | grep -q "rda.suse.com/auth-seed:"; then
    echo "✗ 03: shared provisioning should NOT emit auth-seed (no PVC to drift against)"
    FAIL=$((FAIL + 1))
else
    echo "✓ 03: shared provisioning correctly skips auth-seed annotation"
    PASS=$((PASS + 1))
fi

echo
echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
