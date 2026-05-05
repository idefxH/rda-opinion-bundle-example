# Helm Templates

| Template | Renders |
|----------|---------|
| `deployment.yaml` | App Deployment + sidecars + binding volume mounts + checksum annotation |
| `service.yaml` | App ClusterIP Service |
| `ingress.yaml` | App Ingress (when `suse-library.ingress.enabled`) |
| `ingress-ui.yaml` | Per-service UI Ingress (grafana, prometheus, dex) |
| `binding-secret.yaml` | Per-service binding Secret (host/port/credentials) |
| `_helpers.tpl` | Shared helpers: enabledServices, validateConsistency, bindingSecretFrom, loadMappings |
| `_crds.tpl` | Generic CRD renderer for DO-0004 Phase 2 |
