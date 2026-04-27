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
