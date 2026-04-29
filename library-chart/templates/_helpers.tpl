{{/*
Common name of the project. Defaults to the release name if .Values.name is unset.
*/}}
{{- define "suse-library.name" -}}
{{- default .Release.Name .Values.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels applied to every resource produced by this library.
*/}}
{{- define "suse-library.labels" -}}
app.kubernetes.io/name: {{ include "suse-library.name" . }}
app.kubernetes.io/managed-by: {{ .Release.Service | default "rda" }}
app.kubernetes.io/instance: {{ .Release.Name }}
rda.suse.com/library-version: {{ .Chart.Version }}
{{- end -}}

{{/*
Selector labels — subset of common labels that should not change across
revisions (otherwise existing Deployments cannot find their Pods).
*/}}
{{- define "suse-library.selectorLabels" -}}
app.kubernetes.io/name: {{ include "suse-library.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
DSL helpers — added in v0.10 for the unified `services[]` block.

The DSL coexists with the legacy <chart>.* blocks (Phase 1, see PROPOSAL).
Library templates consume the DSL for binding-secret rendering, app env
projection, and audit labels. The legacy blocks still feed the AppCo
sub-charts via Helm's standard sub-chart values resolution.

`suse-library.dsl.services` returns the project's services[] list, or
an empty list when not declared.
*/}}
{{- define "suse-library.dsl.services" -}}
{{- if .Values.services -}}
{{- toYaml .Values.services -}}
{{- else -}}
[]
{{- end -}}
{{- end -}}

{{/*
`suse-library.dsl.findByType` returns the FIRST service of a given type, or
nothing if none. Use as: {{- $svc := include "suse-library.dsl.findByType"
(dict "type" "postgresql" "Values" .Values) | fromYaml -}}.
*/}}
{{- define "suse-library.dsl.findByType" -}}
{{- $type := .type -}}
{{- range $i, $svc := .Values.services -}}
{{- if eq $svc.type $type -}}
{{- toYaml $svc -}}
{{- break -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
`suse-library.dsl.findByBinding` returns the FIRST service with a given
binding name, or nothing if none.
*/}}
{{- define "suse-library.dsl.findByBinding" -}}
{{- $binding := .binding -}}
{{- range $i, $svc := .Values.services -}}
{{- if eq $svc.binding $binding -}}
{{- toYaml $svc -}}
{{- break -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
`suse-library.dsl.validateConsistency` fails loud if the DSL and the legacy
<chart>.* blocks disagree on key fields (auth.user.password vs auth.password,
etc.). Phase 1: the dev writes both; we ensure they don't drift.
Phase 1.5: the rda CLI pre-processor will write the legacy blocks from the
DSL, eliminating drift.
*/}}
{{- define "suse-library.dsl.validateConsistency" -}}
{{- range $i, $svc := .Values.services -}}
{{- $type := $svc.type -}}
{{- $legacy := index $.Values $type | default dict -}}
{{- if eq $type "postgresql" -}}
{{- if and $legacy.enabled (and $svc.auth $svc.auth.user) -}}
{{- if and $svc.auth.user.password $legacy.auth -}}
{{- if and $legacy.auth.password (ne $svc.auth.user.password $legacy.auth.password) -}}
{{- fail (printf "DSL drift: services[type=postgresql].auth.user.password (%s) != postgresql.auth.password (%s). Phase 1 requires the two views to agree until the rda CLI pre-processor lands. See rda-devx-catalog/PROPOSAL.md." $svc.auth.user.password $legacy.auth.password) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{/* Add similar checks for redis, grafana as those types land in services[] */}}
{{- end -}}
{{- end -}}

{{/*
`suse-library.dsl.envFromBinding` projects the standard <BINDING>_* env
vars referencing the binding-secret. Used in deployment.yaml for each
service in services[]. Yields proper YAML at the env: list level.

The shape is :
  - { name: <BINDING>_HOST,     valueFrom: { secretKeyRef: { name: <release>-<binding>-binding, key: host     } } }
  - { name: <BINDING>_PORT,     valueFrom: { secretKeyRef: { name: <release>-<binding>-binding, key: port     } } }
  - { name: <BINDING>_USERNAME, valueFrom: { secretKeyRef: { name: <release>-<binding>-binding, key: username } } } (when present)
  ...

The set of projected keys per service type is documented in CATALOG.md.
*/}}
{{- define "suse-library.dsl.envFromBinding" -}}
{{- $svc := .svc -}}
{{- $release := .release -}}
{{- $bindingUpper := upper $svc.binding | replace "-" "_" -}}
{{- $secret := printf "%s-%s-binding" $release $svc.binding -}}
- name: {{ $bindingUpper }}_HOST
  valueFrom: { secretKeyRef: { name: {{ $secret }}, key: host } }
- name: {{ $bindingUpper }}_PORT
  valueFrom: { secretKeyRef: { name: {{ $secret }}, key: port } }
{{- if eq $svc.type "postgresql" }}
- name: {{ $bindingUpper }}_USERNAME
  valueFrom: { secretKeyRef: { name: {{ $secret }}, key: username } }
- name: {{ $bindingUpper }}_PASSWORD
  valueFrom: { secretKeyRef: { name: {{ $secret }}, key: password } }
- name: {{ $bindingUpper }}_DATABASE
  valueFrom: { secretKeyRef: { name: {{ $secret }}, key: database } }
{{- else if eq $svc.type "redis" }}
- name: {{ $bindingUpper }}_PASSWORD
  valueFrom: { secretKeyRef: { name: {{ $secret }}, key: password } }
{{- else if eq $svc.type "grafana" }}
- name: {{ $bindingUpper }}_URL
  valueFrom: { secretKeyRef: { name: {{ $secret }}, key: url } }
- name: {{ $bindingUpper }}_ADMIN_USER
  valueFrom: { secretKeyRef: { name: {{ $secret }}, key: adminUser } }
- name: {{ $bindingUpper }}_ADMIN_PASSWORD
  valueFrom: { secretKeyRef: { name: {{ $secret }}, key: adminPassword } }
{{- end }}
{{- end -}}

{{/*
`suse-library.dsl.validatePassthrough` fails loud when a service entry sets
the same AppCo chart path both via the unified DSL fields and via the
service's `passthrough:` block. The DSL is the recommended path; passthrough
is the escape hatch for fields the DSL doesn't cover. When they collide,
silently dropping either value would hide developer intent — so we fail
with both locations and a "pick one" hint.

Documented in idefxH/rda-docs/concepts/passthrough.md (rule #3) and
idefxH/rda-docs/concepts/dsl.md (Validation check #4). Implementation of
idefxH/rda-opinion-bundle-example#37.

Sentinel pattern: `_RDA_NONE_` distinguishes "not set" from "set to a
falsy value" (e.g. `enabled: false`). A non-sentinel value on both sides
of a known DSL↔passthrough mapping triggers the fail.
*/}}
{{- define "suse-library.dsl.validatePassthrough" -}}
{{- $sentinel := "_RDA_NONE_" -}}
{{- range $i, $svc := .Values.services -}}
{{- $type := $svc.type -}}
{{- $pt := $svc.passthrough | default dict -}}
{{- $provisioning := $svc.provisioning | default "local" -}}
{{/*
   Skip collision checks for non-local services: when provisioning is shared
   or external, the AppCo sub-chart for $svc.type is NOT deployed for this
   binding, so passthrough has no sub-chart values to collide with. Devs who
   write passthrough on a shared/external service have only themselves to
   blame; we can't usefully check the collision.
*/}}
{{- if ne $provisioning "local" -}}{{- continue -}}{{- end -}}
{{- if eq $type "postgresql" -}}
{{- include "suse-library.dsl._collide" (dict "svc" $svc "pt" $pt "sentinel" $sentinel "dslPath" "persistence.enabled" "ptPath" "persistence.enabled" "dslKeys" (list "persistence" "enabled") "ptKeys" (list "persistence" "enabled")) -}}
{{- include "suse-library.dsl._collide" (dict "svc" $svc "pt" $pt "sentinel" $sentinel "dslPath" "persistence.size" "ptPath" "persistence.size" "dslKeys" (list "persistence" "size") "ptKeys" (list "persistence" "size")) -}}
{{- include "suse-library.dsl._collide" (dict "svc" $svc "pt" $pt "sentinel" $sentinel "dslPath" "metrics.enabled" "ptPath" "metrics.enabled" "dslKeys" (list "metrics" "enabled") "ptKeys" (list "metrics" "enabled")) -}}
{{- include "suse-library.dsl._collide" (dict "svc" $svc "pt" $pt "sentinel" $sentinel "dslPath" "auth.admin.password" "ptPath" "auth.postgresPassword" "dslKeys" (list "auth" "admin" "password") "ptKeys" (list "auth" "postgresPassword")) -}}
{{- include "suse-library.dsl._collide" (dict "svc" $svc "pt" $pt "sentinel" $sentinel "dslPath" "auth.user.name" "ptPath" "auth.username" "dslKeys" (list "auth" "user" "name") "ptKeys" (list "auth" "username")) -}}
{{- include "suse-library.dsl._collide" (dict "svc" $svc "pt" $pt "sentinel" $sentinel "dslPath" "auth.user.password" "ptPath" "auth.password" "dslKeys" (list "auth" "user" "password") "ptKeys" (list "auth" "password")) -}}
{{- include "suse-library.dsl._collide" (dict "svc" $svc "pt" $pt "sentinel" $sentinel "dslPath" "auth.user.database" "ptPath" "auth.database" "dslKeys" (list "auth" "user" "database") "ptKeys" (list "auth" "database")) -}}
{{- include "suse-library.dsl._collide" (dict "svc" $svc "pt" $pt "sentinel" $sentinel "dslPath" "resources.requests.cpu" "ptPath" "primary.resources.requests.cpu" "dslKeys" (list "resources" "requests" "cpu") "ptKeys" (list "primary" "resources" "requests" "cpu")) -}}
{{- include "suse-library.dsl._collide" (dict "svc" $svc "pt" $pt "sentinel" $sentinel "dslPath" "resources.requests.memory" "ptPath" "primary.resources.requests.memory" "dslKeys" (list "resources" "requests" "memory") "ptKeys" (list "primary" "resources" "requests" "memory")) -}}
{{- include "suse-library.dsl._collide" (dict "svc" $svc "pt" $pt "sentinel" $sentinel "dslPath" "resources.limits.cpu" "ptPath" "primary.resources.limits.cpu" "dslKeys" (list "resources" "limits" "cpu") "ptKeys" (list "primary" "resources" "limits" "cpu")) -}}
{{- include "suse-library.dsl._collide" (dict "svc" $svc "pt" $pt "sentinel" $sentinel "dslPath" "resources.limits.memory" "ptPath" "primary.resources.limits.memory" "dslKeys" (list "resources" "limits" "memory") "ptKeys" (list "primary" "resources" "limits" "memory")) -}}
{{- else if eq $type "redis" -}}
{{- include "suse-library.dsl._collide" (dict "svc" $svc "pt" $pt "sentinel" $sentinel "dslPath" "auth.password" "ptPath" "auth.password" "dslKeys" (list "auth" "password") "ptKeys" (list "auth" "password")) -}}
{{- include "suse-library.dsl._collide" (dict "svc" $svc "pt" $pt "sentinel" $sentinel "dslPath" "persistence.enabled" "ptPath" "master.persistence.enabled" "dslKeys" (list "persistence" "enabled") "ptKeys" (list "master" "persistence" "enabled")) -}}
{{- include "suse-library.dsl._collide" (dict "svc" $svc "pt" $pt "sentinel" $sentinel "dslPath" "metrics.enabled" "ptPath" "metrics.enabled" "dslKeys" (list "metrics" "enabled") "ptKeys" (list "metrics" "enabled")) -}}
{{- include "suse-library.dsl._collide" (dict "svc" $svc "pt" $pt "sentinel" $sentinel "dslPath" "resources.requests.cpu" "ptPath" "master.resources.requests.cpu" "dslKeys" (list "resources" "requests" "cpu") "ptKeys" (list "master" "resources" "requests" "cpu")) -}}
{{- include "suse-library.dsl._collide" (dict "svc" $svc "pt" $pt "sentinel" $sentinel "dslPath" "resources.requests.memory" "ptPath" "master.resources.requests.memory" "dslKeys" (list "resources" "requests" "memory") "ptKeys" (list "master" "resources" "requests" "memory")) -}}
{{- include "suse-library.dsl._collide" (dict "svc" $svc "pt" $pt "sentinel" $sentinel "dslPath" "resources.limits.cpu" "ptPath" "master.resources.limits.cpu" "dslKeys" (list "resources" "limits" "cpu") "ptKeys" (list "master" "resources" "limits" "cpu")) -}}
{{- include "suse-library.dsl._collide" (dict "svc" $svc "pt" $pt "sentinel" $sentinel "dslPath" "resources.limits.memory" "ptPath" "master.resources.limits.memory" "dslKeys" (list "resources" "limits" "memory") "ptKeys" (list "master" "resources" "limits" "memory")) -}}
{{- else if eq $type "grafana" -}}
{{- include "suse-library.dsl._collide" (dict "svc" $svc "pt" $pt "sentinel" $sentinel "dslPath" "auth.admin.name" "ptPath" "adminUser" "dslKeys" (list "auth" "admin" "name") "ptKeys" (list "adminUser")) -}}
{{- include "suse-library.dsl._collide" (dict "svc" $svc "pt" $pt "sentinel" $sentinel "dslPath" "auth.admin.password" "ptPath" "adminPassword" "dslKeys" (list "auth" "admin" "password") "ptKeys" (list "adminPassword")) -}}
{{- include "suse-library.dsl._collide" (dict "svc" $svc "pt" $pt "sentinel" $sentinel "dslPath" "ingress.enabled" "ptPath" "ingress.enabled" "dslKeys" (list "ingress" "enabled") "ptKeys" (list "ingress" "enabled")) -}}
{{- include "suse-library.dsl._collide" (dict "svc" $svc "pt" $pt "sentinel" $sentinel "dslPath" "resources.requests.cpu" "ptPath" "resources.requests.cpu" "dslKeys" (list "resources" "requests" "cpu") "ptKeys" (list "resources" "requests" "cpu")) -}}
{{- include "suse-library.dsl._collide" (dict "svc" $svc "pt" $pt "sentinel" $sentinel "dslPath" "resources.requests.memory" "ptPath" "resources.requests.memory" "dslKeys" (list "resources" "requests" "memory") "ptKeys" (list "resources" "requests" "memory")) -}}
{{- include "suse-library.dsl._collide" (dict "svc" $svc "pt" $pt "sentinel" $sentinel "dslPath" "resources.limits.cpu" "ptPath" "resources.limits.cpu" "dslKeys" (list "resources" "limits" "cpu") "ptKeys" (list "resources" "limits" "cpu")) -}}
{{- include "suse-library.dsl._collide" (dict "svc" $svc "pt" $pt "sentinel" $sentinel "dslPath" "resources.limits.memory" "ptPath" "resources.limits.memory" "dslKeys" (list "resources" "limits" "memory") "ptKeys" (list "resources" "limits" "memory")) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
`suse-library.dsl._collide` is the per-pair check called from validatePassthrough.
Inputs: svc, pt (passthrough block), sentinel, dslPath/ptPath (display strings
for the error message), dslKeys/ptKeys (lists of nested key names for `dig`).

Note: helm's `dig` walks N keys with a final default. We pass our sentinel as
the default so we can distinguish "not set" from "set to a falsy value".
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
`suse-library.dsl._dig` walks a nested map by a list of keys and returns the
leaf value as a string, or the sentinel string when any intermediate key is
missing. Helm's built-in `dig` works for known-depth lookups but is awkward
for variable-length lists; this wrapper keeps the call sites uniform.
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
`suse-library.dsl.bindingSecretFrom` renders a SBS binding-secret for a
single DSL service entry. Used by binding-secret.yaml.

The host/port resolution depends on `services[].provisioning`:

  - `local` (default): per-type convention (`<release>-<type>` for postgresql
    and grafana, `<release>-<type>-master` for redis). The library deploys a
    sub-chart and the binding-secret points at it.

  - `shared`: read from `.Values.defaults.shared_services[<type>]`, which
    the corp overlay populates with the canonical platform-services
    endpoints. Fails loud if the overlay has no entry for this type.

  - `external`: read from the per-service `endpoint:` block. Fails loud if
    `endpoint:` is missing or incomplete.

Credentials (auth.*) are sourced from the DSL the same way regardless of
provisioning: the platform team manages the Vault path, projects reference
it by path. See rda-docs/operator.md Step 6 for the pattern.
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
{{- /* Resolve host/port/scheme depending on provisioning. */ -}}
{{- $host := "" -}}
{{- $port := "" -}}
{{- $scheme := "" -}}
{{- if eq $provisioning "local" -}}
  {{- if eq $svc.type "postgresql" -}}{{- $host = printf "%s-%s" $release $svc.type -}}{{- $port = "5432" -}}
  {{- else if eq $svc.type "redis" -}}{{- $host = printf "%s-%s-master" $release $svc.type -}}{{- $port = "6379" -}}
  {{- else if eq $svc.type "grafana" -}}{{- $host = printf "%s-%s" $release $svc.type -}}{{- $port = "80" -}}{{- $scheme = "http" -}}
  {{- else -}}{{- fail (printf "Unsupported service type %q for binding %q in DSL v1alpha1 (provisioning=local). Supported types: postgresql, redis, grafana." $svc.type $svc.binding) -}}
  {{- end -}}
{{- else if eq $provisioning "shared" -}}
  {{- /* dig() requires plain map[string]interface{}, but $root.Values is chartutil.Values; walk via index instead */ -}}
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
type: Opaque
stringData:
  type: {{ $svc.type | quote }}
  provider: rda-appco
  host: {{ $host | quote }}
  port: {{ $port | quote }}
{{- if eq $svc.type "postgresql" }}
  username: {{ $svc.auth.user.name | default "app" | quote }}
  password: {{ required (printf "services[binding=%s].auth.user.password is required for type=postgresql" $svc.binding) $svc.auth.user.password | quote }}
  database: {{ required (printf "services[binding=%s].auth.user.database is required for type=postgresql" $svc.binding) $svc.auth.user.database | quote }}
{{- else if eq $svc.type "redis" }}
  password: {{ required (printf "services[binding=%s].auth.password is required for type=redis" $svc.binding) $svc.auth.password | quote }}
{{- else if eq $svc.type "grafana" }}
  url: {{ printf "%s://%s:%s" $scheme $host $port | quote }}
  adminUser: {{ $svc.auth.admin.name | default "admin" | quote }}
  adminPassword: {{ required (printf "services[binding=%s].auth.admin.password is required for type=grafana" $svc.binding) $svc.auth.admin.password | quote }}
{{- end }}
{{- end -}}
