# rda-opinion-bundle-example

Example opinion bundle for the [rda CLI](https://github.com/idefxH/rda-cli).

This bundle is the reference fixture for end-to-end testing of `rda` against
real artifacts. It demonstrates the expected structure of an opinion bundle
that platform engineering teams will build for their own organizations.

## Structure

```
rda-opinion-bundle-example/
├── rda-bundle.yaml           # bundle manifest (rda reads this)
├── service-catalog.yaml      # approved service types and providers
├── library-chart/            # SUSE library chart (rda eject pulls from here)
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
└── templates/
    └── web-nodejs/           # one scaffolding template
        ├── template.yaml     # template metadata (rda templates show reads this)
        ├── Chart.yaml        # standalone Helm chart for scaffolded projects
        ├── values.yaml       # default project values
        ├── templates/        # rendered K8s resources (inlined library output for v0)
        ├── Tiltfile          # inner-loop config
        ├── Dockerfile        # BCI-based image build
        ├── package.json      # Node.js project skeleton
        └── src/index.js      # Express app reading /bindings/database
```

## Use

Point `rda` at this bundle via the `RDAConfig` (extension or `RDA_CONFIG` env):

```yaml
bundle_url: https://github.com/idefxH/rda-opinion-bundle-example.git
bundle_ref: main
cache_dir: ~/.cache/rda
appco_registry: dp.apps.rancher.io
```

Then:

```bash
rda templates list
rda templates show web-nodejs
rda new my-app --template web-nodejs   # 'my-app' is your application's name; pick anything domain-meaningful
cd my-app && tilt up
```

## v0 scope (what works, what doesn't)

**Works:**
- `rda new <name> --template web-nodejs` produces a complete self-contained Helm chart
- `rda templates list` and `rda templates show web-nodejs` resolve from the manifest
- The scaffolded project compiles and deploys to a local K3s/Rancher Desktop with `helm install` or `tilt up`

**Limited:**
- `rda eject` works against the stub library chart but is more meaningful when
  templates depend on a real library via `Chart.yaml` dependencies — that design
  comes in v0.2 of this bundle when rda's `new` command is extended to copy
  the library chart into the project's `charts/` directory automatically.
- The Tiltfile uses `docker_build` rather than the SUSE Tilt extension's
  `suse_app` helper. The extension is in a separate repo (in progress) and
  templates will switch to it when it ships.
- The default Dockerfile uses BCI base images. The `pack` buildpack-based
  build path lands when the SUSE-AppCo buildpacks are productized.

## Catalogue

The bundle's catalogue (which AppCo charts you can opt into via
`services[]`) lives at:

- `library-chart/dsl-mappings.yaml` — machine-readable per-chart
  mapping (DSL fields → chart values, `binding_secret` projections,
  `service.host`/`port`/`ports` shape).
- [`reference/catalog.md`](https://github.com/idefxH/rda-docs/blob/main/reference/catalog.md)
  in rda-docs — human-readable reference covering each chart's
  connectivity, auth, persistence, UI, metrics, logs, OIDC, RBAC,
  tracing, CRDs, bootstrap, and resource budget.
- [`concepts/dsl.md`](https://github.com/idefxH/rda-docs/blob/main/concepts/dsl.md)
  — the unified DSL shape (`services[].type`, `auth.*`,
  `persistence.*`, `bootstrap.*`, `overrides.*`, ...).
- [`concepts/scaffolds.md`](https://github.com/idefxH/rda-docs/blob/main/concepts/scaffolds.md)
  — what `rda add-service <type> <binding>` writes for each chart.

Read `catalog.md` before adding a new chart to the bundle.

## Template-time gates (Layer 2 of the layered-defense model)

The library helpers run gates at every `helm template` invocation —
every `tilt up`, every `rda upgrade`, every `rda promote`. These are
**Layer 2** of RDA's four-layer defense model. The canonical reference
is [`rda-docs/concepts/gates.md`](https://github.com/idefxH/rda-docs/blob/main/concepts/gates.md);
the anchor in the rda CLI spec is the `BEHAVIOR: promote` NOTES in
[`rda-cli/rda.md`](https://github.com/idefxH/rda-cli/blob/main/rda.md)
under "Layered-defense model".

Scoped to the rendered DSL — these gates fire before any manifest
reaches a cluster, and run identically on the dev's laptop and in CI.

### Active checks

- **`suse-library.dsl.validateConsistency`** — fails the render if
  any `services[]` entry has an empty `binding`, an unknown `type`
  (not in `library-chart/dsl-mappings.yaml`), or a duplicate
  `binding`. Catches typos before deployment.
- **`suse-library.dsl.validatePassthrough`** — fails the render if
  a service entry sets the same path twice: once via the DSL and
  once via `passthrough:`. The collision keys come from each
  chart's `values_mapping` in `dsl-mappings.yaml`, so the check
  stays in sync with the catalogue.
- **auth-seed drift** — for stateful charts (those with
  `auth_seed_paths` declared in dsl-mappings.yaml), the binding
  Secret carries an `rda.suse.com/auth-seed` annotation. If the dev
  edits an auth field after first init of the PVC, the freshly
  computed seed mismatches the cluster's; render fails loud with
  the nuke recipe so the dev knows the chart's sub-init won't
  re-run for the new credentials.

### Why template-time matters

These checks are **complementary** to image-level gates (Layer 1,
`suse_app(...)` in tilt-extension-suse-rda) and deployment-level
gates (Layer 3, `rda promote`). The library helpers see what no
other layer sees: the actual render of the project's DSL after
overlay merge but before `kubectl apply`. A buildpack does not see
the DSL; `rda promote`'s `forbidden_charts` does not see the
rendered binding-secret structure; admission controllers see the
final manifest but lose the `services[]` provenance. Failing here
is the cheapest place to fail — `tilt up` exits in seconds with a
specific DSL key in the error message.

## Persistence model

The library chart's catalogue draws a line between **stateful** and **observability/cache** services:

| Service     | `persistence.enabled` default | Why                                                                                |
|-------------|-------------------------------|------------------------------------------------------------------------------------|
| postgresql  | `true` (size: 1Gi)            | Seeded data must survive `tilt down` — devs lose trust if their data evaporates.   |
| grafana     | `false`                       | Dashboards/datasources are config, not data. Re-seed from sidecar configmaps.      |
| prometheus  | `false`                       | Scrape data is regenerated within minutes; persisting it on a laptop is overkill.  |

The pattern: **flip persistence on for any chart whose value lives in seeded rows / blobs**, leave it off for anything whose state is regenerable from configuration.

Override locally with `<chart>.persistence.enabled: false` (or `true`) in your project's `values.yaml`.

### Nuke recipe — clean slate

PVCs accumulate across re-installs (Helm doesn't delete them automatically). When you want a clean slate:

```bash
kubectl delete pvc -l app.kubernetes.io/instance=<release-name>
# or for everything in a namespace:
kubectl delete pvc --all -n <namespace>
```

Run this *after* `tilt down` / `helm uninstall` and *before* re-installing.

`rda doctor` will surface a warning when accumulated PVCs grow past a threshold (issue tracked separately).

## License

Apache-2.0 (templates, library chart, code skeletons).
