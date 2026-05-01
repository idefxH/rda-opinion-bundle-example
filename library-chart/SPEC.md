# suse-library

## META
Deployment:   helm-library-chart
Version:      0.11.22
Spec-Schema:  0.1.0
Author:       François-Xavier Houard <fx.houard@gmail.com>
License:      Apache-2.0
Verification: none
Safety-Level: QM

`suse-library` is the Helm library chart at the heart of the SUSE
Rancher Developer Access opinion bundle. It encapsulates the
application Deployment, the Service Binding Specification (SBS) wiring,
and the references to the SUSE Application Collection (AppCo) sub-charts
that projects opt into via `services[]` DSL entries.

This SPEC.md is the canonical contract: what the library guarantees,
which keys it consumes, which resources it emits, which invariants must
hold across templates. Code (helpers + templates) follows the spec, and
every behaviour change requires a spec update in the same commit
(see CONTRIBUTING.md).

The companion `rda` CLI's `rda.md` spec sits at the consumer side of
the same DSL — it scaffolds projects, projects services[] into chart-
specific values overlays, and runs library-aware doctor checks.

## CONVENTIONS

- `<release>` — the Helm release name (the `name:` arg to `helm install`,
  also `{{ .Release.Name }}` at template time).
- `<chart>` — an AppCo chart name like `postgresql`, `redis`,
  `prometheus`, `grafana`. Every reference is verbatim, no alias.
- `<binding>` — the symbolic name a project's app uses to reach a
  service (env-var prefix, Secret name suffix, SBS mount).
- `services[]` — the unified DSL, written by the dev (or by `rda
  add-service`) at `deploy/values.yaml` under `suse-library.services`.
  Projects scaffolded before bundle 0.11.13 used `chart/values.yaml`;
  both layouts are accepted by `rda` and the Tilt extension via
  auto-detection so older projects keep working without migration.

## BEHAVIOR: services-iteration
Constraint: required

Every chart template that walks the `services[]` DSL list MUST iterate
the **enabled subset** computed by `suse-library.dsl.enabledServices`,
not raw `.Values.services`. Single source of truth across all consumer
templates: a disabled service stays inert at every layer (no
binding-secret, no env var, no volume, no mount, no chart-level
`<chart>.enabled` flip).

Enforced templates:
- `templates/binding-secret.yaml` — renders one Secret per enabled entry
- `templates/deployment.yaml` — env (envFromBinding), volume mounts,
  volume Secret references — all on the enabled subset
- `templates/service.yaml` (no services iteration today; may grow)
- `templates/ingress.yaml` (no services iteration today; may grow)

Test guard: `tests/services-iteration-grep/` greps every file under
`library-chart/templates/` for `range.*\.Values\.services`. A match
without an `enabledServices`-derived `$enabled` in scope fails the test
loud at PR review. See LESSONS at the end for the live e2e bug that
motivated this invariant.

Helper definition (in `templates/_helpers.tpl`):

  {{- define "suse-library.dsl.enabledServices" -}}
    iterates .Values.services, filters where !hasKey(svc, 'enabled')
    OR svc.enabled == true; returns JSON-encoded list (Helm named
    templates can only return strings; consumers do `| fromJsonArray`).
  {{- end -}}

## BEHAVIOR: dep-defaults-presence
Constraint: required

Every Helm dep declared in `library-chart/Chart.yaml` MUST have a
matching `<chart>.enabled: false` (or any boolean, but conventionally
false) default key in `library-chart/values.yaml`. Missing the default
makes Helm's `condition: <chart>.enabled` a NO-OP — the dep loads
unconditionally on every install, regardless of whether the project
opted in via services[].

Discovered live: redis dep added in #71 without the corresponding
default → every project pulled redis even when only postgresql was in
services[]. Closed in #75.

Test guard: `tests/dep-defaults-presence/` walks every dep in
`library-chart/Chart.yaml` and checks `library-chart/values.yaml` for a
`<chart>.enabled` key. Fails loud naming the missing chart.

## BEHAVIOR: manifest-version-sync
Constraint: required

`library-chart/Chart.yaml`'s `version` field and
`rda-bundle.yaml`'s `library_chart.version` field MUST be equal in
every commit. The bundle manifest is what `rda upgrade` reads to
compute the upgrade target — drift makes `rda upgrade` silently lie
("already up to date" at the manifest's stale version while the chart
is newer).

Discovered live: 4 consecutive bumps (0.11.5/6/7/8) shipped with the
manifest stuck at 0.11.4. Closed in #78. Test added then.

Test guard: `tests/manifest-version-sync/` (already present).

## BEHAVIOR: dsl-mappings-target-validity
Constraint: required

Every `values_mapping` target path in `library-chart/dsl-mappings.yaml`
MUST be parseable by `rda render` (rda-cli's `internal/render` package).
The contract:
- Path components separated by `.`
- Bracket notation `name[N]` denotes an array index (closes
  rda-cli#75); the projection grows the list with nil placeholders
- Malformed brackets (`hosts[`, `hosts[]`, `hosts[abc]`) are rejected
  loud
- The leaf may be either a scalar (e.g. `chart.auth.password`) or a
  list element (`chart.ingress.hosts[0]`)

Discovered live: prometheus + grafana ingress.host singular projected
to `chart.ingress.hosts[0]`. Without bracket support the literal key
`hosts[0]` was written instead of a list — Helm rendered no Ingress.
Closed in rda-cli#75.

Test guard: `tests/dsl-mappings-targets-valid/` parses every target
path with the same rules `rda render` uses, fails on malformed or
unsupported syntax. Currently parked until rda-cli's projection.go
is published as a re-usable parser; today the bundle relies on
rda-cli's tests covering the same surface.

## BEHAVIOR: binding-secret-schema
Constraint: required

Every binding-secret rendered by `templates/binding-secret.yaml` MUST
follow the schema:

  Secret name:           `<release>-<binding>-binding`
  Mounted at (in pod):   `/bindings/<binding>/`
  Labels (mandatory):
    app.kubernetes.io/name      <release>
    app.kubernetes.io/managed-by Helm
    app.kubernetes.io/instance  <release>
    rda.suse.com/library-version <chart-version>
    rda.suse.com/provisioning   local | shared | external
    service.binding/binding-name <binding>
    service.binding/binding-type <chart>
  Annotations (mandatory when stateful, i.e. auth_seed_paths declared):
    rda.suse.com/source         services[binding=<binding>].type=<chart>.provisioning=<prov>
    rda.suse.com/helper         suse-library.dsl.bindingSecretFrom
    rda.suse.com/auth-seed      <16-char sha256 of auth fields>
  stringData keys (always present):
    type                        the AppCo chart name
    provider                    rda-appco | <overlay-defined> | <user-defined>
    host                        Service FQDN (release-templated)
    port                        chart-default port (string, quoted)
  stringData keys (conditionally present, per dsl-mappings.yaml binding_secret):
    username, password, database, url, adminUser, adminPassword, …

The 12-factor env-var projection in `_helpers.tpl envFromBinding` reads
this Secret's keys, projecting `<BINDING>_<KEY>` env vars (uppercase,
snake_case from the SBS-canonical key) PLUS any `env_aliases` declared
in dsl-mappings (e.g. `username` aliased to `user` for libpq).

Test guard: `tests/binding-secret-schema/` runs `helm template` on a
fixture project and asserts every binding-secret matches the schema.

## BEHAVIOR: ingress-conventions
Constraint: required

Two ingress paths exist in the library:

1. **App-level ingress** — `suse-library.ingress.enabled` + `hosts:
   [list]`. Renders one Ingress fronting the application's Service.
   Plural list canonical (matches the DSL convention everywhere).

2. **Service-level ingress** — declared via the DSL at
   `services[].ingress.enabled` + `hosts: [...]`. Projected by `rda
   render` to the chart-native `<chart>.ingress.hosts` (or
   `<chart>.server.ingress.hosts` for prometheus, per dsl-mappings).
   The chart-native Ingress is the authoritative one. Bundle 0.11.9
   flipped `<chart>.ui.expose: true` to `false` so the library-emitted
   auto-Ingress at `templates/ingress-ui.yaml` no longer duplicates
   the chart-native one. Devs who need the library auto-Ingress
   (override host without touching the chart's own ingress block)
   flip `ui.expose` back to true explicitly.

Singular `services[].ingress.host: <str>` is back-compat-supported via
the bracket-notation projection (`grafana.ingress.hosts[0]`); plural
is the canonical form.

## BEHAVIOR: validateConsistency
Constraint: required

`templates/_helpers.tpl::suse-library.dsl.validateConsistency` runs at
every helm template invocation (called from `binding-secret.yaml`).
Checks (on the **enabled** subset only — disabled entries are inert
scaffolds, not failure conditions):

- every entry has a non-empty `binding`
- every entry has a recognised `type` (must be in dsl-mappings.yaml)
- bindings are unique within services[]
- for stateful types (auth_seed_paths declared): if a binding-secret
  already exists in the cluster (= chart was deployed before), its
  `rda.suse.com/auth-seed` annotation must match the freshly-computed
  seed. Mismatch means the dev edited an auth field after first init
  of the PVC; chart sub-init won't re-run, the new credentials don't
  take, runtime fails with confusing auth errors. Fails loud at
  template time with the nuke recipe. Closed bundle issue #63.

Chart-level enable is derived by `rda render` and lives only in the
auto-generated overlay (`deploy/.rda/values.generated.yaml`); never
hand-written into `deploy/values.yaml`.

---

## MILESTONE: 0.11.0
Status: released

- Initial `suse-library` library chart with the unified DSL
  (`services[]`).
- `templates/_helpers.tpl` ships data-driven helpers reading
  `dsl-mappings.yaml` instead of hardcoded if/else arms — adding a
  chart = one YAML entry.
- Pre-DSL `<chart>.enabled` gated fallback shipped alongside for
  back-compat. Removed in 0.11.22 (see milestone below).

## MILESTONE: 0.11.1
Status: released

- Bug fix: helper indentation produced invalid YAML on consecutive
  binding-secrets. Restructured `bindingSecretFrom` to emit clean
  doc separators.

## MILESTONE: 0.11.2
Status: released

- BEHAVIOR/validateConsistency: stateful charts (auth_seed_paths
  declared in dsl-mappings.yaml) get the auth-seed annotation on
  their binding-secret. Closes bundle #63 (auth drift on PVC re-deploy).

## MILESTONE: 0.11.3
Status: released

- New chart catalogued: `prometheus` (29.x). Joins postgresql,
  redis, grafana in the dsl-mappings.yaml v1alpha1 lineup.

## MILESTONE: 0.11.4
Status: released

- Bug fix: `redis` declared in Chart.yaml as a dep with
  `condition: redis.enabled`. Without #75's defaults follow-up the
  dep loaded by default — closed in 0.11.7.

## MILESTONE: 0.11.5
Status: released

- BEHAVIOR/dsl-mappings: redis entry rewritten for AppCo's
  `architecture: standalone` default — Service is `<release>-redis`
  (no `-master` HA-mode suffix). values_mapping for persistence
  + resources rewired to AppCo's PodTemplate-based schema.

## MILESTONE: 0.11.6
Status: released

- BEHAVIOR/services-iteration introduced: new helper
  `enabledServices` filters `services[].enabled == true` (default true
  if absent). `binding-secret.yaml` + validateConsistency consume the
  filtered set. Closes the rda-cli#67 inert-scaffold contract.

## MILESTONE: 0.11.7
Status: released

- BEHAVIOR/dep-defaults-presence: missing `redis: { enabled: false }`
  default added to `library-chart/values.yaml`. Closes the silent
  redis-deploys-by-default bug from 0.11.4.

## MILESTONE: 0.11.8
Status: released

- BEHAVIOR/dsl-mappings: `ingress.hosts` plural canonical alongside
  the back-compat singular `ingress.host`. Pairs with rda-cli#75's
  bracket-notation projection.
- Bundle template `chart/values.yaml`: app-level ingress default
  switched to `<name>.localtest.me` (universal wildcard DNS) with
  `<name>.localhost` shipped as a commented sibling for macOS/Linux.
- BEHAVIOR/manifest-version-sync introduced: `rda-bundle.yaml`'s
  `library_chart.version` synced to 0.11.8. Test guard added at
  `tests/manifest-version-sync/`.

## MILESTONE: 0.11.9
Status: released

- BEHAVIOR/ingress-conventions: `<chart>.ui.expose` default flipped
  to `false` for prometheus + grafana. Library auto-Ingress is now
  opt-in only; chart-native Ingress (driven by DSL services[].ingress)
  is the canonical path. Closes a duplication caught live (two
  Ingresses for grafana UI — chart-native + library auto).

## MILESTONE: 0.11.10
Status: released

- BEHAVIOR/services-iteration extended: `templates/deployment.yaml`
  now iterates the `enabledServices` helper for env, volumeMounts,
  and volumes. Closes a drift caught live: a project with a disabled
  service (the inert-default scaffold) had its app pod fail with
  `MountVolume.SetUp failed: secret <release>-<binding>-binding not
  found` — binding-secret correctly skipped the disabled entry, but
  deployment iterated raw `.Values.services` and tried to mount the
  missing Secret. Single source of truth restored.

## MILESTONE: 0.11.11
Status: in-progress

- BEHAVIOR/services-iteration enforced by a new test:
  `tests/services-iteration-grep/` greps every file under
  `templates/` for `range.*\.Values\.services` and fails loud if
  found without an `enabledServices`-derived `$enabled` upstream.
- BEHAVIOR/dep-defaults-presence enforced by a new test:
  `tests/dep-defaults-presence/` ensures every chart dep in
  `Chart.yaml` has a matching `<chart>.enabled` default key in
  `values.yaml`.
- New `library-chart/SPEC.md` (this file) — the PCD canonical contract
  for everything above.
- `CONTRIBUTING.md` mandates SPEC.md updates before any behavior
  change. Adds a checklist matching the `rda-cli/rda.md` workflow:
  spec → code → tests → version bump in lockstep across all four
  files (library Chart.yaml, rda-bundle.yaml, template Chart.yaml,
  SPEC.md META.Version).

## MILESTONE: 0.11.14
Status: in-progress

- `dsl-mappings.yaml` `service.host` for all four catalogued charts
  (postgresql, redis, prometheus, grafana) moves from bare-name
  templates (`{{ .Release.Name }}-postgresql`) to FQDN templates
  (`{{ .Release.Name }}-postgresql.{{ .Release.Namespace }}.svc.cluster.local`).
  NS Phase C per `idefxH/rda-cli#74`. (rebased over 0.11.13 rename PR)
- Why FQDN: NS Phase A made the deploy namespace explicit per project
  and per developer (multi-dev shared cluster pattern,
  `{{.project}}-{{.user}}`). Phase C unlocks the cross-namespace
  shared-binding case (UC5) — a `provisioning: shared` postgres
  deployed in a third namespace, consumed by two project namespaces.
  Bare-name templates only resolve within the same namespace; FQDN
  resolves anywhere via cluster-DNS.
- Bare-name back-compat: bare names still work *within* the same
  namespace because Kubernetes DNS resolves unqualified names against
  the pod's own namespace. So projects scaffolded by rda-cli pre-0.1.43
  (no namespace block; bindings + workload land in the same namespace)
  keep working through the binding-secret env var even though the var
  now contains the FQDN. Apps that connect by hostname treat
  `host.ns.svc.cluster.local` and `host` interchangeably when both
  resolve.
- Companion change in `tilt-extension-suse-rda` (PR stacked on
  Phase A's `feature/ns-phase-a-tiltfile`): `workload_name_for()` now
  substitutes `{{ .Release.Namespace }}` in addition to
  `{{ .Release.Name }}`, then strips the FQDN suffix
  (`.<ns>.svc.cluster.local`) to recover the bare workload name —
  k8s_resource registers by Deployment / StatefulSet name, not by
  Service FQDN. Idempotent on bare-name templates so the strip is
  safe to apply across both the pre-0.11.14 and post-0.11.14 shapes.
- Manifest version sync: `library-chart/Chart.yaml` and
  `rda-bundle.yaml::library_chart.version` both bumped to 0.11.14 in
  the same commit. The `manifest-version-sync` test guard catches
  drift if either is missed.

---

## LESSONS

This section is a running post-mortem — every spec-relevant bug we
catch live gets a one-paragraph entry here, anchoring the BEHAVIOR
sections above. The format trades brevity for traceability: a future
contributor reading SPEC.md sees both the rule AND the live evidence
that produced it.

**Lesson 1 — services-iteration drift (0.11.10).** A project with a
service scaffolded by `rda add-service prometheus metrics` (which
writes `enabled: false` per the inert-by-default contract from
rda-cli#67) had its app pod fail with `MountVolume.SetUp failed:
secret payments-metrics-binding not found`. binding-secret.yaml
correctly skipped the disabled entry; deployment.yaml still iterated
raw `.Values.services`. Two pieces of the same chart machinery, two
iteration targets, contract silently broke at runtime. Fix:
deployment.yaml uses enabledServices. Lesson: **invariants implicit
across files are zero-cost to break and high-cost to debug.**
Externalise into SPEC.md, lock with a test.

**Lesson 2 — dep-defaults absent (0.11.7).** PR #71 added redis as a
Helm dep on `library-chart/Chart.yaml` with `condition: redis.enabled`
— but did NOT add the corresponding `redis: { enabled: false }` default
in `library-chart/values.yaml`. Helm's contract: when the path is
missing entirely from values, the condition has no effect — the dep
loads unconditionally. The bug shipped through 0.11.4–0.11.6 because
nothing in the contributor flow caught the missing default. Fix in
#75. Lesson: **chart-level defaults aren't optional, they're part of
the contract. Externalise the rule, lock with a test.**

**Lesson 3 — manifest version drift (0.11.8).** `rda-bundle.yaml`'s
`library_chart.version` field — read by `rda upgrade` to resolve the
target version — was missed across 4 consecutive library bumps. Result:
`rda upgrade` lied with `already up to date 0.11.4` while library was
at 0.11.8. Fix in #78. Test added then. Lesson: **same principle —
invariants across files don't enforce themselves.**

**Lesson 4 — host singular vs plural (0.11.8 + rda-cli#75).** The DSL
exposed `services[].ingress.host` (singular) as the only field. Devs
mentally reached for `hosts: [...]` (plural list) matching the
app-level convention `suse-library.ingress.hosts`. `rda render`
silently ignored the unknown key, no Ingress rendered, no Tilt UI link.
Fix: dsl-mappings supports both, plural canonical. Lesson:
**inconsistency between DSL layers is a UX bug. Same shape across the
stack.**

These four lessons share a class: **contracts that span multiple files
without a check are bugs waiting to happen.** Every BEHAVIOR section
above pairs with a test guard precisely to make these classes
unproducable on a fresh PR.

---

## MILESTONE: 0.11.13
Status: in-progress

- Bundle template directory rename: `templates/web-nodejs/chart/` →
  `templates/web-nodejs/deploy/`. The directory's purpose is to hold
  what gets deployed to Kubernetes; calling it `deploy/` makes that
  obvious to a newcomer cloning the repo. The prior name `chart/`
  was conceptually overloaded — it sounded like an arbitrary helm
  chart we'd publish to a registry, when in fact it's the project's
  own deployment surface.
- New `templates/web-nodejs/deploy/README.md` — explains the
  directory's contract: what each file is, who edits it, why it's
  called `deploy/`, and the load-bearing rule that app source stays
  at the project root and never under `deploy/`.
- Template files updated: `templates/web-nodejs/Tiltfile` passes
  `chart_path='deploy'` explicitly to `suse_app(...)`. Project
  README + `deploy/values.yaml` comments switched from `chart/...`
  to `deploy/...` references.
- Companion changes (separate PRs):
  - `idefxH/rda-cli` — `internal/project/detect.go` and
    `cmd/new.go::vendorLibraryChart` accept `deploy/` (preferred)
    and fall back to `chart/` for projects scaffolded before this
    milestone.
  - `idefxH/tilt-extension-suse-rda` — auto-detects `deploy/` vs
    `chart/` so existing projects that pass `chart_path='chart'`
    keep working.
- Manifest version sync: `library-chart/Chart.yaml` and
  `rda-bundle.yaml::library_chart.version` both bumped to 0.11.13.

## MILESTONE: 0.11.15
Status: in-progress

- Catalogue gains a 5th chart: **dex** (OIDC + OAuth2 IdP). Unlike the
  4 prior charts, dex is NOT in the AppCo catalogue — pulled from the
  upstream `https://charts.dexidp.io` repo at chart 0.24.0 (app 2.44.0).
  This is also the first chart in the catalogue with a non-OCI repo;
  helm dep update handles both shapes transparently.
- `library-chart/dsl-mappings.yaml` gains a `dex:` entry:
  - `service.host`: `<release>-dex.<ns>.svc.cluster.local` (FQDN per
    NS Phase C convention)
  - `service.port`: 5556 (HTTP issuer endpoint; gRPC 5557 + HTTPS 5554
    are off by default and opt-in via passthrough)
  - `values_mapping`: minimal — just `issuer`, `ingress.{enabled,host}`,
    `metrics.enabled` (ServiceMonitor), and the resources block.
    Everything else (storage, connectors, oauth2 clients,
    staticPasswords) goes through `passthrough.config.*`.
  - **NEW**: `chart_defaults` field — literal fill-in values the rda
    renderer writes after `values_mapping`. Used here to fill
    `dex.ingress.hosts[0].paths` with the standard root-path
    ImplementationSpecific entry the dex chart requires (the unified
    DSL writes `ingress.hosts: [str]`, the dex chart wants
    `hosts: [{host, paths}]` — chart_defaults bridges the shape gap
    so devs writing simple-string hosts get a working Ingress).
    Optional on every entry; absent on the AppCo charts whose schemas
    already match the DSL shape. See rda-cli 0.1.49 milestone for
    the renderer-side plumbing.
  - `binding_secret`: type/provider/host/port/url/issuer. The
    `url` and `issuer` keys carry the OIDC issuer URL; consuming
    apps read `DEX_URL` (12-factor projection) to bootstrap their
    OIDC client.
  - No `auth_seed_paths`: dex's storage is configurable (memory /
    kubernetes / postgres). Memory (default scaffold) has no
    persistent state to seed; kubernetes-CRD storage is server-
    managed; postgres-backed storage is a cross-binding concern that
    belongs on the postgres binding's auth-seed declaration, not
    here.
- `library-chart/values.yaml`: `dex.enabled: false` default added.
  Comment reminds that the dex chart REQUIRES `config:` to be set
  or its pod crashloops at startup — the project's
  `deploy/values.yaml` supplies `passthrough.config.{issuer,storage,
  enablePasswordDB}` (the `rda add-service dex` scaffold does this).
- Tilt extension auto-discovery picks up dex's ingress block via the
  same `<chart>.ingress` → Tilt UI link path that grafana already
  uses; no Tiltfile changes needed.
- Companion changes (separate PRs):
  - `idefxH/rda-cli` — `cmd/add_service.go::dslDefaultsFor` gains a
    `case "dex":` arm that writes the bootstrap config (issuer URL
    pointing at the in-cluster Service, storage.memory,
    enablePasswordDB) into `passthrough.config` so a fresh scaffold
    boots without manual editing.
  - `idefxH/rda-e2e-tests` — new scenario asserts the binding-secret
    carries the issuer URL, dex pod is Ready, the discovery endpoint
    `/.well-known/openid-configuration` returns 200, and (when
    ingress.enabled) the Ingress resource carries the hosts so the
    Tilt UI shows clickable links.
- Discovered: planned addition. dex was the smallest IdP we could
  validate the catalog-extension flow against without dragging in
  Keycloak's heavier footprint (Java + DB).
- Spec META.Version 0.11.13 → 0.11.15. Skips 0.11.14 — that slot
  was the in-flight Phase D test fixture which already shipped via
  the bundle Phase C+D combined merge. The version sequencing here
  reflects the reality of merged commits, not the open-PR ordering.

## MILESTONE: 0.11.16
Status: in-progress

- Two more AppCo charts in the catalogue: **mariadb** (sister to
  postgresql, same auth + persistence + auth-seed posture) and
  **apache-kafka** (KRaft mode 4.x — no zookeeper). Catalog count
  goes from 5 → 7. mariadb's chart shape mirrors postgresql closely
  in dsl-mappings (same auth.user.{name,password,database} +
  auth.admin.password projections); kafka's DSL surface is
  intentionally minimal (persistence + metrics only) — SASL /
  multi-broker config goes through passthrough because the
  user/password DSL shape doesn't fit kafka's bootstrap-servers +
  topic-ACLs idiom.
- New library-chart knob: **`service.enabled`** (default true).
  Worker / batch templates that don't accept inbound traffic flip it
  to false to skip the Service resource. Pairs with the
  conditional-probes change in deployment.yaml — readinessProbe is
  now skipped when `probes.readiness` is null/absent (was
  unconditional before). Web shapes keep both enabled by default,
  so no behaviour change for postgresql / redis / grafana /
  prometheus / dex projects.
- Two new templates registered in rda-bundle.yaml: **web-go**
  (Go 1.26 net/http server, multi-stage build using AppCo go +
  go-dev images) and **worker-nodejs** (long-running consumer, no
  HTTP). Languages with both AppCo build (`-dev-` flavoured) and
  runtime (slim) images: nodejs (existing), go (new). Java /
  OpenJDK is also in AppCo with the same shape — deferred to a
  follow-on (issue tracked in rda-opinion-bundle-example#templates-jvm).
- Companion changes (separate PRs):
  - `idefxH/rda-cli` — `cmd/add_service.go::dslDefaultsFor` gains
    `case "mariadb":` and `case "apache-kafka":` arms.
  - `idefxH/rda-e2e-tests` — new scenarios 08-add-mariadb-query,
    09-add-kafka-produce-consume, 10-template-web-go,
    11-template-worker-nodejs.
- Discovered: planned addition. dex (0.11.15) was the catalog-extension
  shake-out; mariadb + kafka are the proof that the data-driven catalog
  scales, web-go + worker-nodejs are the proof that the template
  shape generalises beyond web-nodejs.
- Spec META.Version 0.11.15 → 0.11.16.

## MILESTONE: 0.11.22
Status: in-progress

- Pre-DSL `<chart>.enabled` fallback ripped out. From 0.11.0 through
  0.11.21 the library shipped a back-compat path: when `services[]`
  was absent, the templates fell through to `legacy.envForSqlDb /
  envForUrlOnly / envForUiWithAdmin / bindingMount / bindingVolume /
  sqlBindingSecret / urlBindingSecret / uiBindingSecret` helpers in
  `_helpers.tpl`, projecting whatever the dev set under
  `<chart>.auth.*` into env vars and Secrets directly. The DSL has
  been the only supported authoring path since 0.11.6 (rda-cli#67's
  inert-scaffold contract); the v0.11.0–0.11.21 dev population has
  fully migrated. Carrying both paths doubled the surface area in
  every template review and produced two answers to "where do
  credentials come from?" — confusing newcomers reading the chart.
- Removals:
  - `templates/_helpers.tpl` — dropped 8 `suse-library.legacy.*`
    defines (≈120 lines).
  - `templates/deployment.yaml` — dropped 3 `{{- if not .Values.services }}`
    branches that called the legacy helpers for env, mounts, volumes.
  - `templates/binding-secret.yaml` — dropped the if/else fallback;
    only the DSL-driven loop remains.
  - `library-chart/values.yaml` — pruned ≈120 lines of comments
    referencing the legacy path, the v0.7 history, and the
    superseded SCHEMA.md / PROPOSAL.md docs that never materialised.
  - `library-chart/Chart.yaml` — description rewrite: drops the
    "AppCo verbatim, no alias" + "12-factor uppercase prefix" lines
    that had migrated into `concepts/dsl.md` long ago.
  - `templates/{web-go,web-nodejs,worker-nodejs}/Tiltfile` — dropped
    the "Legacy path: every catalogued chart with `<chart>.enabled:
    true` gets a port-forward" comment block; replaced with the
    current "auto-discovered from services[] entries" wording.
- Comment hygiene pass on the rest of the chart, removing stale
  "Phase 1" / "Phase 2" / "Phase 2.5" markers and the 0.11.0-era
  references to fields that no longer exist.
- No Helm output changes for any project that already adopted the
  DSL (which is everyone — `rda doctor` has flagged any non-DSL
  project since 0.1.40).
- Spec META.Version 0.11.16 → 0.11.22 (skips 0.11.17–0.11.21, all
  of which shipped DSL-evolution features tracked under their own
  PR commits but never got individual SPEC.md milestones).
