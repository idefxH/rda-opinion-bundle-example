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
rda new payment-service --template web-nodejs
cd payment-service && tilt up
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
