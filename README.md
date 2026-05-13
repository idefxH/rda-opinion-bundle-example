# RDA Opinion Bundle

The opinion bundle that powers [rda CLI](https://github.com/idefxH/rda-cli).
Contains the chart catalog, project templates, and the library chart.

## Structure

```
rda-opinion-bundle-example/
├── rda-bundle.yaml                    ← bundle manifest
├── library-chart/                     ← the Helm library chart
│   ├── dsl-mappings.yaml              ← THE SOURCE OF TRUTH (16 chart types)
│   ├── Chart.yaml                     ← AppCo sub-chart dependencies
│   ├── values.yaml                    ← defaults (each chart enabled: false)
│   ├── templates/                     ← Helm templates (deployment, secrets, etc.)
│   ├── tests/                         ← 20 invariant test suites
│   └── scripts/                       ← maintenance scripts
└── templates/                         ← project scaffolding templates (11)
    ├── web-go/                        ← Go web service
    ├── web-nodejs/                    ← Node.js web service
    ├── web-java/                      ← Java web service
    ├── worker-go/                     ← Go background worker
    ├── worker-nodejs/                 ← Node.js background worker
    ├── worker-java/                   ← Java background worker
    ├── multi-workload/                ← multi-container project (workloads[] DSL)
    ├── infra-only/                    ← infrastructure services without an app workload
    ├── brownfield-generic/            ← existing source code (auto-detect language)
    ├── brownfield-image/              ← pre-built container image
    └── brownfield-helm/               ← existing Helm chart
```

## Source of truth

**`library-chart/dsl-mappings.yaml`** is the single source of truth for:
- Which chart types are supported (16: postgresql, redis, valkey, mariadb,
  apache-kafka, prometheus, grafana, dex, minio, vault, etcd, nats,
  opensearch, influxdb, harbor, apache-airflow)
- How DSL fields map to chart values
- What binding secrets each chart produces
- What fields are scaffolded by `rda service add`
- What dependencies exist between charts
- What capabilities each chart supports (auth.users, auth.clients, etc.)

The library chart also provides:
- **`workloads[]` DSL** — multi-container support (each workload gets its own image, port, ingress, probes)
- **`domain` field** — top-level domain value available to ingress and auth templates
- **Connection string helpers** — auto-generated `jdbc_url`, `connection_url` binding keys for postgresql, mariadb, and redis

The CLI reads this file at runtime. **Adding a chart is a bundle change,
not a CLI change.**

## Key commands

```bash
# Run all 20 tests
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
