#!/usr/bin/env bash
# cnpg-image-source-switch — verify the CNPG Cluster template picks the
# right postgres image for community vs AppCo chart source, and honors
# an explicit imageName override and a postgres-branch override.
#
# Background (idefxH/rda-opinion-bundle-example#?): with the community
# CNPG operator, the AppCo image (UID 26) makes initdb crash with
#   initdb: could not look up effective user ID 26: user does not exist
# so the image selection MUST match the active chart source.
#
# Signal used by the template: presence of `application-collection`
# in `.Values.global.imagePullSecrets` ⇒ AppCo registry; otherwise
# community (ghcr.io/cloudnative-pg/postgresql).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$(cd "$SCRIPT_DIR/../.." && pwd)"

if ! command -v helm >/dev/null 2>&1; then
  echo "SKIP: helm not on PATH, skipping cnpg-image-source-switch"
  exit 0
fi

WORK="$(mktemp -d -t cnpg-image-switch.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/deploy/templates" "$WORK/deploy/charts"
ln -s "$LIB" "$WORK/deploy/charts/suse-library"
touch "$WORK/deploy/templates/.gitkeep"
cat > "$WORK/deploy/Chart.yaml" <<EOF
apiVersion: v2
name: test
version: 0.1.0
type: application
dependencies:
  - name: suse-library
    version: "*"
    repository: file://charts/suse-library
EOF

emit_values () {
  # $1 = ips-shape (none|map|string)
  # $2 = optional branch (e.g. "16") or empty
  # $3 = optional explicit imageName override or empty
  local shape="$1" branch="$2" override="$3" ipsblock="" branchblock="" overrideblock=""
  case "$shape" in
    none)   ipsblock=$'  global:\n    imagePullSecrets: []' ;;
    map)    ipsblock=$'  global:\n    imagePullSecrets:\n      - name: application-collection' ;;
    string) ipsblock=$'  global:\n    imagePullSecrets:\n      - application-collection' ;;
  esac
  if [ -n "$branch" ]; then
    branchblock=$'    version:\n      postgresql: "'"$branch"$'"'
  fi
  if [ -n "$override" ]; then
    overrideblock="      imageName: $override"
  fi
  cat <<EOF
suse-library:
  name: test
  domain: localtest.me
$ipsblock
  services:
    - binding: db
      type: cnpg
      enabled: true
      auth:
        user:
          password: testpass
  cnpg:
    enabled: true
$branchblock
    cluster:
      instances: 1
$overrideblock
      storage:
        size: 1Gi
      bootstrap:
        initdb:
          database: app
          owner: app
EOF
}

render () {
  helm template test "$WORK/deploy" -f "$WORK/deploy/values.yaml" \
    --show-only charts/suse-library/templates/cnpg-cluster.yaml 2>/dev/null \
    | grep -E '^[[:space:]]+imageName:' | awk '{print $2}' | tr -d '"'
}

fail=0
expect () {
  local label="$1" got="$2" want="$3"
  if [ "$got" = "$want" ]; then
    echo "  ✓ $label → $got"
  else
    echo "  ✗ $label → got=$got want=$want"
    fail=$((fail+1))
  fi
}

# 1. Community baseline (empty global.imagePullSecrets) → ghcr.io image
emit_values none "" "" > "$WORK/deploy/values.yaml"
expect "community (empty list)" "$(render)" "ghcr.io/cloudnative-pg/postgresql:17"

# 2. AppCo (map shape: - name: application-collection) → dp.apps.rancher.io
emit_values map "" "" > "$WORK/deploy/values.yaml"
expect "appco (map shape)" "$(render)" "dp.apps.rancher.io/containers/postgresql:17"

# 3. AppCo (string shape: - application-collection) → dp.apps.rancher.io
emit_values string "" "" > "$WORK/deploy/values.yaml"
expect "appco (string shape)" "$(render)" "dp.apps.rancher.io/containers/postgresql:17"

# 4. Branch override flows through (community + postgresql: 16)
emit_values none 16 "" > "$WORK/deploy/values.yaml"
expect "community + branch=16" "$(render)" "ghcr.io/cloudnative-pg/postgresql:16"

# 5. Explicit imageName override wins over both registry and branch
emit_values none 16 "my-registry.example.com/pg:custom" > "$WORK/deploy/values.yaml"
expect "explicit imageName preserved" "$(render)" "my-registry.example.com/pg:custom"

# 6. Explicit override survives even in AppCo mode
emit_values map "" "my-registry.example.com/pg:custom" > "$WORK/deploy/values.yaml"
expect "explicit override beats appco signal" "$(render)" "my-registry.example.com/pg:custom"

if [ "$fail" -gt 0 ]; then
  echo "FAIL: $fail case(s) failed"
  exit 1
fi
echo "✓ cnpg-image-source-switch: 6 cases passed"
