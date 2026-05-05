# Library Chart Tests

18 invariant test suites that guard the library chart's contracts.
Run all: `for d in */; do bash "$d/run.sh"; done`

| Test | What it guards |
|------|---------------|
| `auth-seed` | Auth-seed annotation determinism |
| `auto-ingress-ui` | UI Ingress only when `ui.expose: true` |
| `binding-secret-multiport-render` | Multi-port binding projection |
| `catalog-consistency` | dsl-mappings ↔ rda-docs catalog parity |
| `dep-defaults-presence` | Every Chart.yaml dep has `<name>.enabled: false` in values.yaml |
| `dsl-mappings-schema` | YAML schema validation of dsl-mappings.yaml |
| `dsl-mappings-target-validity` | values_mapping targets exist |
| `env-aliases` | Env alias projection |
| `manifest-version-sync` | Chart.yaml version matches rda-bundle.yaml |
| `passthrough-collision` | DSL ↔ passthrough collision detection |
| `prometheus` | Prometheus binding invariants |
| `provisioning` | local/shared/external mode handling |
| `services-iteration-grep` | Templates use enabledServices helper, not raw .Values.services |
| `template-go-deps-version-compat` | Go dependency version compat |
| `template-go-sum-present` | go.sum presence |
| `template-nodejs-package-lock-present` | package-lock.json presence |
| `template-pack-build-smoke` | Buildpack build smoke test |
| `template-procfile-package-consistency` | Procfile consistency |
