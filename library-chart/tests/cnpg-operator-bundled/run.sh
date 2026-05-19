#!/usr/bin/env bash
# cnpg-operator-bundled — guard the helm-install-from-flat-export path.
#
# When a project enables a cnpg service and runs `rda export --flat`
# followed by vanilla `helm install`, the resulting chart must carry
# the CloudNativePG operator + its CRDs as a sub-chart. Without that,
# `helm install` fails with:
#   no matches for kind "Cluster" in version "postgresql.cnpg.io/v1"
# because nothing else installs the operator (Tilt's extension does
# this out-of-band, but `helm install` has no such helper).
#
# This test locks in three invariants:
#   1. library-chart/Chart.yaml declares `cloudnative-pg` as a conditional
#      sub-chart dependency, gated on `cloudnative-pg.enabled`.
#   2. dsl-mappings.yaml's cnpg chart_defaults sets
#      `cloudnative-pg.enabled: true` so adding a cnpg service flips
#      the operator on automatically.
#   3. Both stay true after `chart-source.py --mode community` (the
#      operator dep MUST NOT be stripped — it's served from the
#      cnpg community repo, not AppCo OCI).
#   4. `helm template` of a project with cnpg enabled renders the
#      Cluster CR AND the operator Deployment AND the Cluster CRD.
#      Helm 3's kind-ordering then guarantees CRDs are applied before
#      the Cluster CR at install time.
#
# Skips silently when `helm` is not on PATH (matches the convention
# used by helm-template-smoke and cnpg-image-source-switch).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$(cd "$SCRIPT_DIR/../.." && pwd)"

python3 - "$LIB" <<'PY'
import os, sys, yaml

lib_dir = sys.argv[1]

# Invariant 1: Chart.yaml declares cloudnative-pg as conditional dep.
with open(os.path.join(lib_dir, "Chart.yaml")) as f:
    chart = yaml.safe_load(f)

cnpg_dep = next(
    (d for d in chart.get("dependencies", []) if d.get("name") == "cloudnative-pg"),
    None,
)
if cnpg_dep is None:
    sys.stderr.write(
        "ERROR: library-chart/Chart.yaml is missing the `cloudnative-pg` "
        "sub-chart dependency. Without it, `rda export --flat` + "
        "`helm install` fails with `no matches for kind Cluster` because "
        "nothing installs the CNPG operator + CRDs.\n"
    )
    sys.exit(1)

if cnpg_dep.get("condition") != "cloudnative-pg.enabled":
    sys.stderr.write(
        f"ERROR: cloudnative-pg dep must be conditional on "
        f"`cloudnative-pg.enabled`, got "
        f"{cnpg_dep.get('condition')!r}. dsl-mappings flips this flag "
        f"via chart_defaults when a cnpg service is added.\n"
    )
    sys.exit(1)

# Invariant 2: cnpg chart_defaults enables the operator.
with open(os.path.join(lib_dir, "dsl-mappings.yaml")) as f:
    doc = yaml.safe_load(f)

cnpg = doc.get("charts", {}).get("cnpg", {})
versions = cnpg.get("versions", [])
if not versions:
    sys.stderr.write("ERROR: dsl-mappings.yaml charts.cnpg has no versions[]\n")
    sys.exit(1)

defaults = versions[0].get("chart_defaults", {}) or {}
if defaults.get("cloudnative-pg.enabled") is not True:
    sys.stderr.write(
        "ERROR: dsl-mappings.yaml charts.cnpg.versions[0].chart_defaults "
        "must set `cloudnative-pg.enabled: true` so adding a cnpg service "
        "auto-installs the operator. Without it, `helm install` will fail "
        "with `no matches for kind Cluster`.\n"
    )
    sys.exit(1)

print("  ✓ Chart.yaml declares cloudnative-pg sub-chart dep")
print("  ✓ dsl-mappings.yaml cnpg.chart_defaults enables the operator")
PY

# Invariant 3: community-mode toggle preserves the cnpg dep.
TMP_CHART="$(mktemp -t cnpg-community-XXXXXX.yaml)"
cp "$LIB/Chart.yaml" "$TMP_CHART"
trap 'rm -f "$TMP_CHART"' EXIT

# Run chart-source.py against a copy so we don't touch the live file.
COMMUNITY_OUT="$(python3 "$LIB/scripts/chart-source.py" --mode community --chart "$TMP_CHART" 2>&1)"
if ! grep -q "cloudnative-pg" "$TMP_CHART"; then
  echo "ERROR: chart-source.py --mode community stripped the cloudnative-pg dep"
  echo "       (it should only strip oci://dp.apps.rancher.io entries)"
  echo "Output was: $COMMUNITY_OUT"
  exit 1
fi
echo "  ✓ chart-source.py --mode community preserves cloudnative-pg dep"

# Invariant 4: helm template renders operator + CRDs + Cluster CR.
if ! command -v helm >/dev/null 2>&1; then
  echo "  SKIP: helm not on PATH, skipping render check"
  echo "✓ cnpg-operator-bundled: static checks passed"
  exit 0
fi

WORK="$(mktemp -d -t cnpg-bundled.XXXXXX)"
trap 'rm -rf "$WORK"; rm -f "$TMP_CHART"' EXIT

# Build a self-contained library-chart copy with only the
# cloudnative-pg sub-chart declared. `helm dep update` against the
# source Chart.yaml would try to authenticate against the AppCo OCI
# registry (dp.apps.rancher.io) and fail in CI / on fresh clones.
# Stripping the deps down to just cloudnative-pg lets dep update
# fetch from the community helm repo only, with no credentials.
TMP_LIB="$WORK/library-chart"
cp -R "$LIB" "$TMP_LIB"
rm -rf "$TMP_LIB/charts" "$TMP_LIB/Chart.lock"

python3 - "$TMP_LIB/Chart.yaml" <<'PY'
import sys, yaml
p = sys.argv[1]
with open(p) as f:
    chart = yaml.safe_load(f)
chart["dependencies"] = [
    d for d in chart.get("dependencies", []) if d.get("name") == "cloudnative-pg"
]
with open(p, "w") as f:
    yaml.safe_dump(chart, f, sort_keys=False)
PY

if ! helm dep update "$TMP_LIB" >"$WORK/dep-update.log" 2>&1; then
  echo "ERROR: helm dep update failed for the cnpg-only library-chart copy"
  cat "$WORK/dep-update.log"
  exit 1
fi
if ! ls "$TMP_LIB"/charts/cloudnative-pg-*.tgz >/dev/null 2>&1; then
  echo "ERROR: helm dep update did not fetch the cloudnative-pg subchart"
  cat "$WORK/dep-update.log"
  exit 1
fi

mkdir -p "$WORK/deploy/templates" "$WORK/deploy/charts"
ln -s "$TMP_LIB" "$WORK/deploy/charts/suse-library"
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

cat > "$WORK/deploy/values.yaml" <<'EOF'
suse-library:
  name: test
  domain: localtest.me
  services:
    - binding: db
      type: cnpg
      enabled: true
      auth:
        user:
          name: app
          password: testpass
          database: app
  cloudnative-pg:
    enabled: true
  cnpg:
    enabled: true
    cluster:
      instances: 1
      storage:
        size: 1Gi
      bootstrap:
        initdb:
          database: app
          owner: app
EOF

RENDERED="$(helm template test "$WORK/deploy" -f "$WORK/deploy/values.yaml" 2>&1)"

check_kind () {
  local label="$1" pattern="$2"
  local count
  count=$(echo "$RENDERED" | grep -cE "$pattern" || true)
  if [ "$count" -gt 0 ]; then
    echo "  ✓ $label ($count match(es))"
  else
    echo "  ✗ $label: missing from helm template output"
    echo "    pattern: $pattern"
    return 1
  fi
}

fail=0
check_kind "Cluster CR rendered"            "^kind: Cluster$"                              || fail=$((fail+1))
check_kind "Cluster CRD rendered"           "name: clusters.postgresql.cnpg.io"            || fail=$((fail+1))

# Operator chart: anchor on the helm.sh/chart label which is unique to
# the cloudnative-pg sub-chart (the workload Deployment uses a different
# helm.sh/chart label, scoped to suse-library).
# Avoid `set -o pipefail` SIGPIPE noise by capturing with grep -c first.
chart_label_count=$(printf '%s\n' "$RENDERED" | grep -c "helm.sh/chart: cloudnative-pg-" || true)
if [ "$chart_label_count" -gt 0 ]; then
  echo "  ✓ operator chart resources rendered ($chart_label_count labelled resource(s))"
else
  echo "  ✗ operator chart resources missing — cloudnative-pg subchart didn't render"
  fail=$((fail+1))
fi

if [ "$fail" -gt 0 ]; then
  echo
  echo "FAIL: cnpg-operator-bundled detected $fail missing piece(s)."
  echo 'This means "rda export --flat" + "helm install" will hit'
  echo '  no matches for kind "Cluster" in version "postgresql.cnpg.io/v1"'
  echo "because the operator + CRDs aren't being bundled."
  exit 1
fi

echo "✓ cnpg-operator-bundled: operator + CRDs + Cluster CR all bundled"
