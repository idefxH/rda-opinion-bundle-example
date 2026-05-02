#!/usr/bin/env bash
# Smoke test for env_resolved → deployment.yaml emission (rda-cli 0.1.52+,
# library 0.11.28). Replaces the legacy env_aliases test which
# verified the now-retired auto-projection.
#
# The fixture provides env_resolved directly (simulating rda render
# output) and asserts that helm template emits each entry with the
# correct valueFrom.secretKeyRef or value: shape.
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
FIXTURE="$SCRIPT_DIR/01-env-resolved-renders-both-secret-and-value.values.yaml"

OUT="$(helm template demo "$CHART" -f "$FIXTURE" 2>&1)"
RC=$?
if [ $RC -ne 0 ]; then
    echo "✗ helm template failed:"
    echo "$OUT"
    exit 1
fi

PASS=0
FAIL=0
check() {
    local needle="$1"
    if echo "$OUT" | grep -q -F "$needle"; then
        echo "✓ found: $needle"
        PASS=$((PASS + 1))
    else
        echo "✗ missing: $needle"
        FAIL=$((FAIL + 1))
    fi
}

# Each of the 4 secret-ref entries should appear with a secretKeyRef.
check "name: DB_HOST"
check "name: DB_USER"
check "name: DB_USERNAME"
check "name: DB_PASSWORD"

# The literal value entry — composed string resolved by render.
check "name: DATABASE_URL"
check 'value: "postgres://app:pw@demo-db-postgresql:5432/demo"'

# Both DB_USERNAME and DB_USER reference the same Secret key 'username'.
USERNAME_REFS=$(echo "$OUT" | grep -A 5 "name: DB_USERNAME\|name: DB_USER" | grep -c "key: username")
if [ "$USERNAME_REFS" -ne 2 ]; then
    echo "✗ expected DB_USERNAME and DB_USER both to reference key: username, got $USERNAME_REFS matches"
    FAIL=$((FAIL + 1))
else
    echo "✓ DB_USERNAME and DB_USER both reference key: username"
    PASS=$((PASS + 1))
fi

# The legacy auto-projection should NOT emit anything: we did not
# include DB_DATABASE in env_resolved, so it must be absent from the
# rendered deployment env block.
if echo "$OUT" | grep -q "name: DB_DATABASE"; then
    echo "✗ DB_DATABASE leaked into deployment env — auto-projection should be GONE"
    FAIL=$((FAIL + 1))
else
    echo "✓ DB_DATABASE absent (no auto-projection — env list is exactly what env_resolved declared)"
    PASS=$((PASS + 1))
fi

echo
echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
