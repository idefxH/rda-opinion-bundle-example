#!/usr/bin/env bash
# Smoke test for env_aliases: assert the rendered Deployment has both the
# SBS-canonical env vars and the alias spellings.
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
FIXTURE="$SCRIPT_DIR/01-postgres-emits-both-username-and-user.values.yaml"

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

# SBS canonical env vars
check "name: DB_USERNAME"
check "name: DB_PASSWORD"
check "name: DB_DATABASE"
check "name: DB_HOST"
check "name: DB_PORT"

# env_aliases
check "name: DB_USER"
check "name: DB_NAME"

# Both DB_USERNAME and DB_USER reference the same Secret key 'username'
# (the alias points at the original key, not its own copy in the Secret).
USERNAME_REFS=$(echo "$OUT" | grep -A 1 "name: DB_USERNAME\|name: DB_USER" | grep -c "key: username")
if [ "$USERNAME_REFS" -ne 2 ]; then
    echo "✗ expected DB_USERNAME and DB_USER both to reference key: username, got $USERNAME_REFS matches"
    FAIL=$((FAIL + 1))
else
    echo "✓ DB_USERNAME and DB_USER both reference key: username"
    PASS=$((PASS + 1))
fi

echo
echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ]
