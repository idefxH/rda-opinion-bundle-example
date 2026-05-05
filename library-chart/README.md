# Library Chart (suse-library)

The Helm library chart that powers every RDA project. Vendored into
each project at `deploy/charts/suse-library/` by `rda new`.

## Key files

| File | What it does |
|------|-------------|
| `Chart.yaml` | Declares AppCo sub-chart dependencies (postgresql, redis, etc.) with `condition: <chart>.enabled` |
| `values.yaml` | Default values — every chart starts `enabled: false` |
| `dsl-mappings.yaml` | **The data model** — per-chart service host/port, values mapping, binding secret schema, scaffold defaults, capabilities, dependencies |
| `templates/deployment.yaml` | App Deployment with env vars, binding mounts, sidecars, checksum annotation |
| `templates/_helpers.tpl` | Helm helpers: enabledServices, validateConsistency, bindingSecretFrom |
| `templates/_crds.tpl` | Generic CRD renderer (DO-0004 Phase 2) |
| `templates/binding-secret.yaml` | Per-service binding Secret with host/port/credentials |
| `templates/ingress.yaml` | App Ingress (when suse-library.ingress.enabled) |
| `templates/service.yaml` | App Service (ClusterIP) |
| `scripts/sync-from-dsl-mappings.py` | Checks Chart.yaml + values.yaml stay in sync with dsl-mappings |
| `tests/` | 18 invariant test suites |

## dsl-mappings.yaml — the source of truth

**[Maintenance guide](https://github.com/idefxH/rda-docs/blob/main/reference/dsl-mappings-guide.md)** — how to read, write, and maintain entries (render pipeline, template syntax, gotchas, checklist).

This file is the **single source of truth** for:
- Which chart types the catalog supports (15 types)
- How DSL fields map to chart values (`values_mapping`)
- What binding secret keys each chart produces (`binding_secret`)
- What fields `rda service add` scaffolds (`scaffold`)
- What capabilities each chart has (`capabilities`)
- What dependencies exist between charts (`dependencies`)
- Service host/port for binding resolution (`service`)

The CLI reads this file at runtime. Adding a new chart type is a
dsl-mappings.yaml change — no CLI code change needed.

## Adding a new chart

1. Add the chart to `Chart.yaml` dependencies
2. Add `<chart>: { enabled: false }` to `values.yaml`
3. Add the full entry to `dsl-mappings.yaml`
4. Run `python3 scripts/sync-from-dsl-mappings.py` to verify
5. Run `for d in tests/*/; do bash "$d/run.sh"; done` (18 tests)
