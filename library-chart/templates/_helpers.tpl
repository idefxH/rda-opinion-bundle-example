{{/*
Helpers for the SUSE library chart.

Phase 2.5 (data-driven catalog): the per-chart shape of the unified DSL
is read from `library-chart/dsl-mappings.yaml`, not hardcoded if/else
arms. Adding a new chart = one YAML entry; the helpers below loop over
it generically.

The legacy.* helpers further down still target the pre-DSL gated path
(<chart>.enabled). They cover postgresql, prometheus, grafana — the same
catalogue the DSL covers, but rendered without services[]. Phase 1.5
will deprecate the legacy path entirely.
*/}}

{{- define "suse-library.name" -}}
{{- default .Release.Name .Values.name -}}
{{- end -}}

{{- define "suse-library.labels" -}}
app.kubernetes.io/name: {{ include "suse-library.name" . }}
app.kubernetes.io/managed-by: {{ .Release.Service | default "Helm" }}
app.kubernetes.io/instance: {{ .Release.Name }}
rda.suse.com/library-version: {{ .Chart.Version }}
{{- end -}}

{{- define "suse-library.selectorLabels" -}}
app.kubernetes.io/name: {{ include "suse-library.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* ──────────────────────────────────────────────────────────────────────
    DSL helpers (data-driven from dsl-mappings.yaml)
    ────────────────────────────────────────────────────────────────────── */}}

{{/*
suse-library.dsl.loadMappings — load and parse library-chart/dsl-mappings.yaml.
Cached for the duration of the render. The file lives at the chart root, NOT
under templates/, so .Files.Get returns its raw text.
*/}}
{{- define "suse-library.dsl.loadMappings" -}}
{{- $raw := .Files.Get "dsl-mappings.yaml" -}}
{{- if eq $raw "" -}}{{- fail "dsl-mappings.yaml not found at chart root" -}}{{- end -}}
{{- $raw | fromYaml | toJson -}}
{{- end -}}

{{/*
suse-library.dsl.resolveMapping — given a chart name (e.g. "postgresql") and a
root context (.), look up the chart's mapping entry for the version actually
vendored in the project. The version is read from .Chart.Dependencies (the
library-chart's declared deps). The first versions[] entry whose `constraint`
matches via semverCompare wins. When no version is found (e.g. dep was added
without rebuilding the lock), the first versions[] entry is used as fallback.

Args (dict): chart, root.
Returns the entry (a dict) as a JSON string; the caller uses fromJson to
unwrap. We trade JSON ferrying for sub-template return semantics — Helm
named templates can only return strings.

Fails loud if the chart isn't in dsl-mappings.yaml.
*/}}
{{- define "suse-library.dsl.resolveMapping" -}}
{{- $chart := .chart -}}
{{- $root := .root -}}
{{- $mappings := include "suse-library.dsl.loadMappings" $root | fromJson -}}
{{- $charts := index $mappings "charts" | default dict -}}
{{- $entry := index $charts $chart -}}
{{- if not $entry -}}
{{- fail (printf "dsl-mappings.yaml has no entry for chart %q. Add one or fix the services[].type. See library-chart/dsl-mappings.yaml." $chart) -}}
{{- end -}}
{{- $versions := index $entry "versions" | default list -}}
{{- if eq (len $versions) 0 -}}
{{- fail (printf "dsl-mappings.yaml: charts.%s.versions[] is empty" $chart) -}}
{{- end -}}
{{- /* Find the actual vendored version from .Chart.Dependencies */ -}}
{{- $vendored := "" -}}
{{- range $dep := $root.Chart.Dependencies -}}
  {{- if eq $dep.Name $chart -}}{{- $vendored = $dep.Version -}}{{- end -}}
{{- end -}}
{{- $picked := dict -}}
{{- if ne $vendored "" -}}
  {{- range $v := $versions -}}
    {{- $constraint := index $v "constraint" -}}
    {{- /* semverCompare returns true when version satisfies constraint. */ -}}
    {{- if and (eq (kindOf $picked) "map") (eq (len $picked) 0) -}}
      {{- if semverCompare $constraint (semver $vendored | toString) -}}
        {{- $picked = $v -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- /* Fallback: first entry. Logged via a no-op so devs see it in --debug. */ -}}
{{- if and (eq (kindOf $picked) "map") (eq (len $picked) 0) -}}
  {{- $picked = first $versions -}}
{{- end -}}
{{- $picked | toJson -}}
{{- end -}}

{{/*
suse-library.dsl.services — return the services[] list, defaulting to empty.
Mirrors the pattern used by other DSL helpers — a single point to fix when
the location of services[] changes (e.g. moves under a sub-key).
*/}}
{{- define "suse-library.dsl.services" -}}
{{- if .Values.services -}}
{{- toJson .Values.services -}}
{{- else -}}
[]
{{- end -}}
{{- end -}}

{{/*
suse-library.dsl.findByType — return the first services[] entry of the given
type, or empty dict. Used by callers that want to know "do we have any
postgresql binding in this project?".
*/}}
{{- define "suse-library.dsl.findByType" -}}
{{- $needle := .type -}}
{{- $found := dict -}}
{{- range $svc := .Values.services -}}
  {{- if and (eq (kindOf $found) "map") (eq (len $found) 0) -}}
    {{- if eq $svc.type $needle -}}{{- $found = $svc -}}{{- end -}}
  {{- end -}}
{{- end -}}
{{- $found | toJson -}}
{{- end -}}

{{/*
suse-library.dsl.findByBinding — return the services[] entry matching binding
name, or empty dict. Used by `rda explain` and the dsl helper unit tests.
*/}}
{{- define "suse-library.dsl.findByBinding" -}}
{{- $needle := .binding -}}
{{- $found := dict -}}
{{- range $svc := .Values.services -}}
  {{- if and (eq (kindOf $found) "map") (eq (len $found) 0) -}}
    {{- if eq $svc.binding $needle -}}{{- $found = $svc -}}{{- end -}}
  {{- end -}}
{{- end -}}
{{- $found | toJson -}}
{{- end -}}

{{/*
suse-library.dsl.authSeed — compute a deterministic short hash of the
auth fields that a stateful chart bakes into its PVC at first init.
Used both:
  - as the value of the rda.suse.com/auth-seed annotation on the
    binding-secret (so we know what was baked the first time)
  - as the comparison input in validateConsistency's drift check
    (to detect that the dev edited an auth field after first deploy
    and would need a PVC reset).

Args (dict): svc, mapping (the version-resolved chart entry from
dsl-mappings.yaml).

Returns: 16-hex-char short SHA256 of the joined "path=value\n" lines.
Empty when the chart has no auth_seed_paths declared (stateless types
like grafana). Empty seed = no annotation emitted = no drift check.
*/}}
{{- define "suse-library.dsl.authSeed" -}}
{{- $svc := .svc -}}
{{- $mapping := .mapping -}}
{{- $paths := index $mapping "auth_seed_paths" | default list -}}
{{- if gt (len $paths) 0 -}}
{{- $parts := list -}}
{{- range $path := $paths -}}
  {{- $keys := splitList "." $path -}}
  {{- $val := include "suse-library.dsl._dig" (dict "obj" $svc "keys" $keys "sentinel" "_RDA_NONE_") -}}
  {{- if eq $val "_RDA_NONE_" -}}{{- $val = "" -}}{{- end -}}
  {{- $parts = append $parts (printf "%s=%s" $path $val) -}}
{{- end -}}
{{- join "\n" $parts | sha256sum | trunc 16 -}}
{{- end -}}
{{- end -}}

{{/*
suse-library.dsl.validateConsistency — sanity checks on services[]. Phase 1
checks:
  - every entry has a non-empty `binding`
  - every entry has a recognised `type` (must be in dsl-mappings.yaml)
  - bindings are unique within services[]
  - for provisioning=local entries: <chart>.enabled must be true. The
    Helm dependency `condition` field on library-chart/Chart.yaml gates
    sub-chart resolution on that flag, and condition is evaluated at
    dep-resolution time — BEFORE `_helpers.tpl` runs. So we can't auto-
    derive the flag from services[]; we can only fail loud here when
    they're out of sync. `rda add-service` writes both halves; this
    check catches the case where someone removes <chart>.enabled
    manually thinking it's redundant with the DSL entry.
  - for stateful types (auth_seed_paths declared): if a binding-secret
    already exists in the cluster (= chart was deployed before), its
    rda.suse.com/auth-seed annotation must match the freshly-computed
    seed. Mismatch means the dev edited an auth field after first init
    of the PVC; chart sub-init won't re-run, the new credentials don't
    take, runtime fails with confusing auth errors. Fail loud at
    template time with the nuke recipe. Closes #63.
*/}}
{{- define "suse-library.dsl.validateConsistency" -}}
{{- $mappings := include "suse-library.dsl.loadMappings" . | fromJson -}}
{{- $known := index $mappings "charts" | default dict -}}
{{- $seen := dict -}}
{{- range $i, $svc := .Values.services -}}
  {{- if eq (toString $svc.binding) "" -}}
  {{- fail (printf "services[%d] has no binding name. Each entry must set 'binding: <name>'." $i) -}}
  {{- end -}}
  {{- if not (hasKey $known $svc.type) -}}
  {{- $supported := keys $known | sortAlpha -}}
  {{- fail (printf "services[binding=%s].type=%q is not catalogued. Supported types (from dsl-mappings.yaml): %s." $svc.binding $svc.type (join ", " $supported)) -}}
  {{- end -}}
  {{- if hasKey $seen $svc.binding -}}
  {{- fail (printf "duplicate binding %q in services[]: each entry needs a unique binding name." $svc.binding) -}}
  {{- end -}}
  {{- $_ := set $seen $svc.binding true -}}
  {{- /* Local provisioning requires the matching <chart>.enabled flag.
         Helm's dep `condition` evaluates before this helper runs, so we
         can only validate post-hoc — but the failure is clear enough
         that the dev fixes it in one edit. */ -}}
  {{- $provisioning := $svc.provisioning | default "local" -}}
  {{- if eq $provisioning "local" -}}
  {{- $chartBlock := index $.Values $svc.type | default dict -}}
  {{- if not (eq (kindOf $chartBlock) "map") -}}{{- $chartBlock = dict -}}{{- end -}}
  {{- if not (eq (index $chartBlock "enabled" | default false) true) -}}
  {{- fail (printf "services[binding=%s].type=%s, provisioning=local — but suse-library.%s.enabled is not true. The Helm dep gates the sub-chart on `condition: %s.enabled`, and condition is evaluated at dep resolution time, so the DSL entry alone can't trigger the dep. Set:\n\n    suse-library:\n      %s:\n        enabled: true\n\n(Or run `rda add-service` which writes both halves automatically.) See rda-docs/concepts/dsl.md#why-the-enabled-flag-is-not-redundant." $svc.binding $svc.type $svc.type $svc.type $svc.type) -}}
  {{- end -}}
  {{- /* Auth-seed drift check (#63). Fires only when:
           1. the chart declares auth_seed_paths in dsl-mappings.yaml
           2. an existing binding-secret carries an auth-seed annotation
              (lookup returns non-nil — i.e. we're at apply time, not at
               helm template --dry-run, AND the chart was deployed before)
         First-deploy: lookup returns nil → skip silently. CI dry-runs:
         lookup returns nil → skip silently. Re-deploy after auth edit:
         seed mismatch → fail loud with nuke recipe. */ -}}
  {{- $vEntry := include "suse-library.dsl.resolveMapping" (dict "chart" $svc.type "root" $) | fromJson -}}
  {{- $authPaths := index $vEntry "auth_seed_paths" | default list -}}
  {{- if gt (len $authPaths) 0 -}}
    {{- $secretName := printf "%s-%s-binding" $.Release.Name $svc.binding -}}
    {{- $namespace := $.Release.Namespace -}}
    {{- $existing := lookup "v1" "Secret" $namespace $secretName -}}
    {{- if $existing -}}
      {{- $annotations := $existing.metadata.annotations | default dict -}}
      {{- $existingSeed := index $annotations "rda.suse.com/auth-seed" | default "" -}}
      {{- if ne $existingSeed "" -}}
        {{- $currentSeed := include "suse-library.dsl.authSeed" (dict "svc" $svc "mapping" $vEntry) -}}
        {{- if ne $existingSeed $currentSeed -}}
        {{- fail (printf "services[binding=%s] auth has changed since this chart's PVC was first initialised (seed %s → %s). %s only initialises its credentials once, on first start of an empty PGDATA. Subsequent re-deploys keep the ORIGINAL credentials/database baked into the volume — your DSL edit is silently ignored, and the runtime fails with confusing auth errors.\n\nTo pick up the new auth values, nuke the volume:\n\n    tilt down\n    kubectl delete pvc -l app.kubernetes.io/instance=%s\n    tilt up\n\nIf you didn't mean to change the auth, revert your DSL edit (re-render against git: rda render --check).\n\nSee idefxH/rda-opinion-bundle-example#63." $svc.binding $existingSeed $currentSeed $svc.type $.Release.Name) -}}
        {{- end -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{/*
suse-library.dsl.envFromBinding — project env vars from a binding-secret.
For every key declared in the chart's binding_secret list, emit a
{ name: <BINDING>_<KEY>, valueFrom: { secretKeyRef: { ... } } } entry.

When a binding_secret entry declares `env_aliases: [name1, name2]`, the
helper emits ADDITIONAL env vars `<BINDING>_<NAMEn>` that all reference
the SAME secret key. Use this to keep SBS-canonical key names in the
Secret (username, database, ...) while also projecting the env-var
spellings the broader ecosystem expects (libpq's PGUSER convention →
DB_USER, JDBC's DB_NAME, etc.). Aliases never appear in the Secret's
stringData — only as additional env-var bindings.

Args (dict): svc, release.
*/}}
{{- define "suse-library.dsl.envFromBinding" -}}
{{- $svc := .svc -}}
{{- $release := .release -}}
{{- $bindingUpper := upper $svc.binding | replace "-" "_" -}}
{{- $secret := printf "%s-%s-binding" $release $svc.binding -}}
{{- $mapping := include "suse-library.dsl.resolveMapping" (dict "chart" $svc.type "root" .root) | fromJson -}}
{{- range $entry := index $mapping "binding_secret" }}
{{- if not (index $entry "skip_env" | default false) }}
{{- /* The env var name uses upper-snake-case: camelCase secret keys (adminUser)
       become ADMIN_USER, kebab-case keys (admin-user) become ADMIN_USER too.
       Sprig's `snakecase` does the camelCase split; replace handles dashes. */ -}}
{{- $secretKey := index $entry "key" -}}
{{- $envKey := ($secretKey | snakecase | upper | replace "-" "_") }}
- name: {{ printf "%s_%s" $bindingUpper $envKey }}
  valueFrom: { secretKeyRef: { name: {{ $secret }}, key: {{ $secretKey }} } }
{{- /* Optional aliases — additional env vars referencing the same Secret
       key. Empty / missing list is fine; we just iterate and emit. */ -}}
{{- range $alias := index $entry "env_aliases" | default list }}
{{- $aliasEnvKey := ($alias | snakecase | upper | replace "-" "_") }}
- name: {{ printf "%s_%s" $bindingUpper $aliasEnvKey }}
  valueFrom: { secretKeyRef: { name: {{ $secret }}, key: {{ $secretKey }} } }
{{- end }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
suse-library.dsl.validatePassthrough — fail loud when a service entry sets
the same path both via the DSL and via `passthrough:`.

The list of DSL→passthrough collisions to check comes from each chart's
values_mapping in dsl-mappings.yaml. The DSL key is the LHS; the
passthrough key is the RHS minus the chart's name prefix (e.g. for redis
the YAML says `redis.master.persistence.enabled` — under `passthrough:`
on a redis service the user would write `master.persistence.enabled`).

Sentinel pattern: `_RDA_NONE_` distinguishes "not set" from "set to a
falsy value".
*/}}
{{- define "suse-library.dsl.validatePassthrough" -}}
{{- $sentinel := "_RDA_NONE_" -}}
{{- $mappings := include "suse-library.dsl.loadMappings" . | fromJson -}}
{{- $charts := index $mappings "charts" | default dict -}}
{{- range $i, $svc := .Values.services -}}
{{- $type := $svc.type -}}
{{- $pt := $svc.passthrough | default dict -}}
{{- $provisioning := $svc.provisioning | default "local" -}}
{{- /* Skip non-local: no sub-chart deployed = no passthrough collision possible */ -}}
{{- if ne $provisioning "local" -}}{{- continue -}}{{- end -}}
{{- $entry := index $charts $type | default dict -}}
{{- $versions := index $entry "versions" | default list -}}
{{- if eq (len $versions) 0 -}}{{- continue -}}{{- end -}}
{{- /* Use the first versions[] entry for collision keys — version-specific
       collisions across chart majors are rare; if needed, future work can
       reuse resolveMapping's lookup logic here. */ -}}
{{- $first := first $versions -}}
{{- $vmap := index $first "values_mapping" | default dict -}}
{{- $prefix := printf "%s." $type -}}
{{- range $dslPath, $valuesPath := $vmap -}}
  {{- /* Strip the chart-name prefix from the chart-level values path to
         get the passthrough sub-path (passthrough is rooted at the chart). */ -}}
  {{- if hasPrefix $prefix $valuesPath -}}
    {{- $ptPath := trimPrefix $prefix $valuesPath -}}
    {{- $dslKeys := splitList "." $dslPath -}}
    {{- $ptKeys := splitList "." $ptPath -}}
    {{- include "suse-library.dsl._collide" (dict "svc" $svc "pt" $pt "sentinel" $sentinel "dslPath" $dslPath "ptPath" $ptPath "dslKeys" $dslKeys "ptKeys" $ptKeys) -}}
  {{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
suse-library.dsl._collide — per-pair check called from validatePassthrough.
Inputs: svc, pt (passthrough block), sentinel, dslPath/ptPath (display
strings), dslKeys/ptKeys (lists of nested key names for `dig`).
*/}}
{{- define "suse-library.dsl._collide" -}}
{{- $svc := .svc -}}
{{- $pt := .pt -}}
{{- $sentinel := .sentinel -}}
{{- $dslVal := include "suse-library.dsl._dig" (dict "obj" $svc "keys" .dslKeys "sentinel" $sentinel) -}}
{{- $ptVal := include "suse-library.dsl._dig" (dict "obj" $pt "keys" .ptKeys "sentinel" $sentinel) -}}
{{- if and (ne $dslVal $sentinel) (ne $ptVal $sentinel) -}}
{{- fail (printf "services[binding=%s].%s is set both via the DSL (=%s) and via passthrough.%s (=%s). Pick one. The DSL is the recommended path; use passthrough only for fields the DSL doesn't cover. See idefxH/rda-docs/concepts/passthrough.md." $svc.binding .dslPath $dslVal .ptPath $ptVal) -}}
{{- end -}}
{{- end -}}

{{/*
suse-library.dsl._dig — walk a nested map by a list of keys, return leaf as
string or sentinel if any key is missing.
*/}}
{{- define "suse-library.dsl._dig" -}}
{{- $obj := .obj -}}
{{- $sentinel := .sentinel -}}
{{- $found := true -}}
{{- $cur := $obj -}}
{{- range $k := .keys -}}
{{- if and $found (kindIs "map" $cur) (hasKey $cur $k) -}}
{{- $cur = index $cur $k -}}
{{- else -}}
{{- $found = false -}}
{{- end -}}
{{- end -}}
{{- if $found -}}
{{- $cur | toString -}}
{{- else -}}
{{- $sentinel -}}
{{- end -}}
{{- end -}}

{{/*
suse-library.dsl.bindingSecretFrom — render a SBS binding-secret for a single
DSL service entry. Used by binding-secret.yaml.

Data-driven: the binding_secret list in dsl-mappings.yaml drives the
stringData. Each entry is one of:
  - {key, literal: <const>}        # always emit this exact string
  - {key, template: "..."}         # tpl-rendered with $.Release.Name in scope
  - {key, from_dsl: <dsl-path>, required: bool, default: <fallback>}

Provisioning:
  - local    : host = chart's mapping.service.host (templated), port = mapping.service.port
  - shared   : host/port from .Values.defaults.shared_services[<type>] (overlay)
  - external : host/port from $svc.endpoint (dev fills in)

The mapping's binding_secret host/port are overridden when provisioning is
shared/external, because in those cases the host doesn't follow the
local-deploy convention.
*/}}
{{- define "suse-library.dsl.bindingSecretFrom" -}}
{{- $svc := .svc -}}
{{- $root := .root -}}
{{- $release := $root.Release.Name -}}
{{- $name := printf "%s-%s-binding" $release $svc.binding -}}
{{- $provisioning := $svc.provisioning | default "local" -}}
{{- if not (or (eq $provisioning "local") (or (eq $provisioning "shared") (eq $provisioning "external"))) -}}
{{- fail (printf "services[binding=%s].provisioning must be 'local', 'shared', or 'external' (got %q). See rda-docs/concepts/dsl.md#provisioning." $svc.binding $provisioning) -}}
{{- end -}}
{{- $mapping := include "suse-library.dsl.resolveMapping" (dict "chart" $svc.type "root" $root) | fromJson -}}
{{- /* Resolve host / port / scheme depending on provisioning */ -}}
{{- $host := "" -}}
{{- $port := "" -}}
{{- $scheme := "" -}}
{{- if eq $provisioning "local" -}}
  {{- $svcSpec := index $mapping "service" | default dict -}}
  {{- $hostTpl := index $svcSpec "host" | default "" -}}
  {{- if eq $hostTpl "" -}}{{- fail (printf "dsl-mappings.yaml: charts.%s.versions[*].service.host is missing" $svc.type) -}}{{- end -}}
  {{- $host = tpl $hostTpl $root -}}
  {{- $port = (index $svcSpec "port" | default "") | toString -}}
  {{- $scheme = index $svcSpec "scheme" | default "http" -}}
{{- else if eq $provisioning "shared" -}}
  {{- $defaults := index $root.Values "defaults" | default dict -}}
  {{- $sharedRoot := index $defaults "shared_services" | default dict -}}
  {{- $sharedMap := index $sharedRoot $svc.type | default dict -}}
  {{- $sharedHost := index $sharedMap "host" | default "" -}}
  {{- if eq $sharedHost "" -}}
  {{- fail (printf "services[binding=%s].provisioning=shared but the overlay has no defaults.shared_services.%s.host. Either configure the overlay (rda-docs/operator.md Step 6 → 'Pre-fill the endpoints in the overlay') or set provisioning: external with an explicit endpoint:." $svc.binding $svc.type) -}}
  {{- end -}}
  {{- $host = $sharedHost -}}
  {{- $port = index $sharedMap "port" | default "" | toString -}}
  {{- $scheme = index $sharedMap "scheme" | default "http" -}}
{{- else if eq $provisioning "external" -}}
  {{- $ep := $svc.endpoint | default dict -}}
  {{- if eq (index $ep "host" | default "") "" -}}
  {{- fail (printf "services[binding=%s].provisioning=external requires endpoint: { host, port, scheme } on the service entry." $svc.binding) -}}
  {{- end -}}
  {{- $host = $ep.host -}}
  {{- $port = $ep.port | default "" | toString -}}
  {{- $scheme = $ep.scheme | default "http" -}}
{{- end -}}
{{- /* Render the Secret. Always start with --- on its own line, including
       a leading newline so consecutive includes from a range loop don't
       get glued together (fixes the multi-service rendering bug). */ -}}

---
apiVersion: v1
kind: Secret
metadata:
  name: {{ $name }}
  labels:
    {{- include "suse-library.labels" $root | nindent 4 }}
    service.binding/binding-name: {{ $svc.binding }}
    service.binding/binding-type: {{ $svc.type }}
    rda.suse.com/provisioning: {{ $provisioning | quote }}
  annotations:
    # rda.suse.com/source documents which DSL key this resource was generated from.
    # Manifesto principle: learning. Devs who inspect a Secret can trace it back
    # to their values.yaml without having to dive into helper code.
    rda.suse.com/source: "services[binding={{ $svc.binding }}].type={{ $svc.type }}.provisioning={{ $provisioning }}"
    rda.suse.com/helper: "suse-library.dsl.bindingSecretFrom"
    {{- /* Auth-seed annotation (#63). Stamps the secret with a hash of
           the auth fields the chart's PVC bakes on first init. On
           re-deploy, validateConsistency reads this annotation back via
           lookup and compares with the freshly-computed seed. Mismatch
           = the dev edited an auth field after first init = PVC reset
           required. Empty when the chart is stateless (no auth_seed_paths
           in dsl-mappings.yaml — grafana, prometheus). Only emitted for
           provisioning=local: shared/external bindings don't have a PVC
           to drift against. */ -}}
    {{- if eq $provisioning "local" -}}
    {{- $authSeed := include "suse-library.dsl.authSeed" (dict "svc" $svc "mapping" $mapping) -}}
    {{- if ne $authSeed "" }}
    rda.suse.com/auth-seed: {{ $authSeed | quote }}
    {{- end -}}
    {{- end }}
type: Opaque
stringData:
{{- range $bsEntry := index $mapping "binding_secret" }}
  {{- $key := index $bsEntry "key" }}
  {{- /* Connectivity keys (host/port/url) are sourced from the provisioning
         resolution above ($host/$port/$scheme), not from the mapping's
         literal/template — the mapping's values are the local-deploy
         convention; shared/external need the overlay/endpoint values. */ -}}
  {{- if eq $key "host" }}
  {{ $key }}: {{ $host | quote }}
  {{- else if eq $key "port" }}
  {{ $key }}: {{ $port | quote }}
  {{- else if eq $key "url" }}
  {{ $key }}: {{ printf "%s://%s:%s" $scheme $host $port | quote }}
  {{- else if hasKey $bsEntry "literal" }}
  {{ $key }}: {{ index $bsEntry "literal" | quote }}
  {{- else if hasKey $bsEntry "template" }}
  {{ $key }}: {{ tpl (index $bsEntry "template") $root | quote }}
  {{- else if hasKey $bsEntry "from_dsl" }}
  {{- $dslPath := index $bsEntry "from_dsl" }}
  {{- $keys := splitList "." $dslPath }}
  {{- $val := include "suse-library.dsl._dig" (dict "obj" $svc "keys" $keys "sentinel" "_RDA_NONE_") }}
  {{- $required := index $bsEntry "required" | default false }}
  {{- $default := index $bsEntry "default" | default "" }}
  {{- if eq $val "_RDA_NONE_" }}
  {{- if $required }}
  {{- fail (printf "services[binding=%s].%s is required for type=%s (per dsl-mappings.yaml)" $svc.binding $dslPath $svc.type) }}
  {{- end }}
  {{ $key }}: {{ $default | quote }}
  {{- else }}
  {{- /* required:true also rejects empty strings — pg, mysql, redis, etc.
         all treat an empty password as "no password" / fall back to env
         vars / silently fail at runtime. Catching here makes the failure
         loud at template time with a clear DSL key in the message. */ -}}
  {{- if and $required (eq $val "") }}
  {{- fail (printf "services[binding=%s].%s is required for type=%s but is empty (\"\"). Set a non-empty value before tilt up — most clients (pg, mysql, redis) treat an empty password as missing and silently fall back, producing a confusing runtime error rather than a clear template-time one. See rda-docs/concepts/dsl.md." $svc.binding $dslPath $svc.type) }}
  {{- end }}
  {{ $key }}: {{ $val | quote }}
  {{- end }}
  {{- end }}
{{- end }}
{{- end -}}

{{/* ──────────────────────────────────────────────────────────────────────
    Legacy-path helpers (issue #5) — pre-DSL <chart>.enabled gated path.
    ────────────────────────────────────────────────────────────────────── */}}

{{- define "suse-library.legacy.envForSqlDb" -}}
{{- $chart := .chart -}}
{{- $rel := .release -}}
{{- $upper := upper $chart -}}
- {name: {{ $upper }}_HOST,     valueFrom: {secretKeyRef: {name: {{ $rel }}-{{ $chart }}-binding, key: host}}}
- {name: {{ $upper }}_PORT,     valueFrom: {secretKeyRef: {name: {{ $rel }}-{{ $chart }}-binding, key: port}}}
- {name: {{ $upper }}_USER,     valueFrom: {secretKeyRef: {name: {{ $rel }}-{{ $chart }}-binding, key: username}}}
- {name: {{ $upper }}_PASSWORD, valueFrom: {secretKeyRef: {name: {{ $rel }}-{{ $chart }}-binding, key: password}}}
- {name: {{ $upper }}_DATABASE, valueFrom: {secretKeyRef: {name: {{ $rel }}-{{ $chart }}-binding, key: database}}}
- {name: DB_HOST,     valueFrom: {secretKeyRef: {name: {{ $rel }}-{{ $chart }}-binding, key: host}}}
- {name: DB_PORT,     valueFrom: {secretKeyRef: {name: {{ $rel }}-{{ $chart }}-binding, key: port}}}
- {name: DB_USER,     valueFrom: {secretKeyRef: {name: {{ $rel }}-{{ $chart }}-binding, key: username}}}
- {name: DB_PASSWORD, valueFrom: {secretKeyRef: {name: {{ $rel }}-{{ $chart }}-binding, key: password}}}
- {name: DB_NAME,     valueFrom: {secretKeyRef: {name: {{ $rel }}-{{ $chart }}-binding, key: database}}}
{{- end -}}

{{- define "suse-library.legacy.envForUrlOnly" -}}
{{- $chart := .chart -}}
{{- $rel := .release -}}
{{- $upper := upper $chart -}}
- {name: {{ $upper }}_URL, valueFrom: {secretKeyRef: {name: {{ $rel }}-{{ $chart }}-binding, key: url}}}
{{- end -}}

{{- define "suse-library.legacy.envForUiWithAdmin" -}}
{{- $chart := .chart -}}
{{- $rel := .release -}}
{{- $upper := upper $chart -}}
- {name: {{ $upper }}_URL,            valueFrom: {secretKeyRef: {name: {{ $rel }}-{{ $chart }}-binding, key: url}}}
- {name: {{ $upper }}_ADMIN_USER,     valueFrom: {secretKeyRef: {name: {{ $rel }}-{{ $chart }}-binding, key: adminUser}}}
- {name: {{ $upper }}_ADMIN_PASSWORD, valueFrom: {secretKeyRef: {name: {{ $rel }}-{{ $chart }}-binding, key: adminPassword}}}
{{- end -}}

{{- define "suse-library.legacy.bindingMount" -}}
- {name: binding-{{ .chart }}, mountPath: /bindings/{{ .chart }}, readOnly: true}
{{- end -}}

{{- define "suse-library.legacy.bindingVolume" -}}
- name: binding-{{ .chart }}
  secret: {secretName: {{ .release }}-{{ .chart }}-binding}
{{- end -}}

{{- define "suse-library.legacy.sqlBindingSecret" -}}
{{- $chart := .chart -}}
{{- $port := .port -}}
{{- $hostSvc := .hostSvc -}}
{{- $root := .root -}}
{{- $vals := index $root.Values $chart -}}
---
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "suse-library.name" $root }}-{{ $chart }}-binding
  labels:
    {{- include "suse-library.labels" $root | nindent 4 }}
    service.binding/binding-name: {{ $chart }}
    service.binding/binding-type: {{ $chart }}
type: Opaque
stringData:
  type: {{ $chart }}
  provider: rda-appco
  host: {{ $hostSvc | quote }}
  port: {{ $port | quote }}
  username: {{ required (printf "%s.auth.username is required when %s.enabled=true" $chart $chart) $vals.auth.username | quote }}
  password: {{ required (printf "%s.auth.password is required when %s.enabled=true" $chart $chart) $vals.auth.password | quote }}
  database: {{ required (printf "%s.auth.database is required when %s.enabled=true" $chart $chart) $vals.auth.database | quote }}
{{- end -}}

{{- define "suse-library.legacy.urlBindingSecret" -}}
{{- $chart := .chart -}}
{{- $port := .port -}}
{{- $hostSvc := .hostSvc -}}
{{- $root := .root -}}
---
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "suse-library.name" $root }}-{{ $chart }}-binding
  labels:
    {{- include "suse-library.labels" $root | nindent 4 }}
    service.binding/binding-name: {{ $chart }}
    service.binding/binding-type: {{ $chart }}
type: Opaque
stringData:
  type: {{ $chart }}
  provider: rda-appco
  host: {{ $hostSvc | quote }}
  port: {{ $port | quote }}
  url: "http://{{ $hostSvc }}"
{{- end -}}

{{- define "suse-library.legacy.uiBindingSecret" -}}
{{- $chart := .chart -}}
{{- $port := .port -}}
{{- $hostSvc := .hostSvc -}}
{{- $adminUser := .adminUser -}}
{{- $adminField := .adminField -}}
{{- $root := .root -}}
{{- $vals := index $root.Values $chart -}}
---
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "suse-library.name" $root }}-{{ $chart }}-binding
  labels:
    {{- include "suse-library.labels" $root | nindent 4 }}
    service.binding/binding-name: {{ $chart }}
    service.binding/binding-type: {{ $chart }}
type: Opaque
stringData:
  type: {{ $chart }}
  provider: rda-appco
  host: {{ $hostSvc | quote }}
  port: {{ $port | quote }}
  url: "http://{{ $hostSvc }}"
  adminUser: {{ index $vals "adminUser" | default $adminUser | quote }}
  adminPassword: {{ required (printf "%s.%s is required when %s.enabled=true" $chart $adminField $chart) (index $vals $adminField) | quote }}
{{- end -}}
