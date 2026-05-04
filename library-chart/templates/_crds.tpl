{{/*
  _crds.tpl — generic CRD renderer for DO-0004 Phase 2.

  Iterates suse-library.crds[] (populated by rda render's CRD projection)
  and renders each as a standalone Kubernetes resource. The CRD objects
  are fully formed by the render pipeline — this template just outputs
  them with proper metadata labels.
*/}}
{{- range $crd := (index .Values "suse-library").crds }}
---
apiVersion: {{ $crd.apiVersion }}
kind: {{ $crd.kind }}
metadata:
  name: {{ $crd.metadata.name }}
  namespace: {{ $.Release.Namespace }}
  labels:
    {{- include "suse-library.labels" $ | nindent 4 }}
    rda.suse.com/source: crd-projection
spec:
  {{- toYaml $crd.spec | nindent 2 }}
{{- end }}
