# RDA Opinion Bundle

The opinion bundle that powers [rda CLI](https://github.com/idefxH/rda-cli).
Contains the chart catalog, project templates, and the library chart.

## Structure

```
rda-opinion-bundle-example/
├── rda-bundle.yaml                    ← bundle manifest
├── library-chart/                     ← the Helm library chart
│   ├── dsl-mappings.yaml              ← THE SOURCE OF TRUTH (15 chart types)
│   ├── Chart.yaml                     ← AppCo sub-chart dependencies
│   ├── values.yaml                    ← defaults (each chart enabled: false)
│   ├── templates/                     ← Helm templates (deployment, secrets, etc.)
│   ├── tests/                         ← 18 invariant test suites
│   └── scripts/                       ← maintenance scripts
└── templates/                         ← project scaffolding templates
    ├── web-go/                        ← Go web service
    ├── web-nodejs/                    ← Node.js web service
    ├── web-java/                      ← Java web service
    ├── worker-go/                     ← Go background worker
    ├── worker-nodejs/                 ← Node.js background worker
    └── worker-java/                   ← Java background worker
```

## Source of truth

**`library-chart/dsl-mappings.yaml`** is the single source of truth for:
- Which chart types are supported (15: postgresql, redis, valkey, mariadb,
  apache-kafka, prometheus, grafana, dex, minio, vault, etcd, nats,
  opensearch, influxdb, harbor)
- How DSL fields map to chart values
- What binding secrets each chart produces
- What fields are scaffolded by `rda service add`
- What dependencies exist between charts
- What capabilities each chart supports (auth.users, auth.clients, etc.)

The CLI reads this file at runtime. **Adding a chart is a bundle change,
not a CLI change.**

## Key commands

```bash
# Run all 18 tests
for d in library-chart/tests/*/; do bash "$d/run.sh"; done

# Check dsl-mappings ↔ Chart.yaml sync
python3 library-chart/scripts/sync-from-dsl-mappings.py

# DSL reference
# See: https://github.com/idefxH/rda-docs/blob/main/reference/dsl.md
```

## Bundle manifest (rda-bundle.yaml)

| Field | Purpose |
|-------|---------|
| `templates[]` | List of project templates with id, language, path |
| `library_chart.oci_ref` | Where the library chart lives (file:// for local) |
| `library_chart.version` | Pinned version |
| `tilt_extension.ref` | Tilt extension version (injected into scaffolded Tiltfiles) |
| `service_catalog[]` | Chart types surfaced by the CLI |
