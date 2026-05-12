# Contributing to `rda-opinion-bundle-example`

This bundle is governed by **PCD** (Post-Coding Development): the
canonical contract lives in `library-chart/SPEC.md`, code follows the
spec, every behavior change requires a spec update in the same commit.

## Workflow

```
You change behavior  →  SPEC.md captures it  →  Code follows  →  Tests lock it in
       ↑                                                                |
       └──────────────────── PR review ─────────────────────────────────┘
```

## Pre-PR checklist

Before opening a PR that changes the library chart's behavior or
catalogue, walk through this list. The four bumps below MUST land in
**the same commit** — drift between any two of them has shipped real
bugs (see SPEC.md LESSONS).

### 1. Spec first

- [ ] `library-chart/SPEC.md` updated with the new BEHAVIOR section, or
      the existing one amended. Reference the issue / PR number.
- [ ] A new `## MILESTONE: X.Y.Z` block at the bottom of SPEC.md
      describing the change (what / why / discovered context). The
      MILESTONE format mirrors `idefxH/rda-cli/rda.md`.
- [ ] `library-chart/SPEC.md`'s `META.Version` field bumped to the new
      version.

### 2. Code

- [ ] Helm template / helper changes implement the spec.
- [ ] `library-chart/Chart.yaml`'s `version` bumped to match `SPEC.md`'s
      `META.Version`.

### 3. Lockstep

- [ ] `rda-bundle.yaml`'s `library_chart.version` bumped to match.
      `rda upgrade` reads THIS field — drift makes it silently lie.
      The `tests/manifest-version-sync/` test asserts equality.
- [ ] `templates/web-nodejs/chart/Chart.yaml`'s `suse-library` dep
      version bumped. Fresh `rda new` projects pin to this.

### 4. Tests

- [ ] If the change establishes a new invariant, add a test under
      `library-chart/tests/<invariant>/` (run.sh + check.py). See
      `services-iteration-grep` and `dep-defaults-presence` for the
      pattern.
- [ ] Run all bundle tests: `for d in library-chart/tests/*/; do bash
      "$d/run.sh"; done`. All must exit 0.

### 5. Specific guards already in place

These tests run on every PR — make sure your change doesn't trip them:

| Test | What it asserts | Failed historically by |
|---|---|---|
| `manifest-version-sync` | `Chart.yaml.version == rda-bundle.yaml.library_chart.version` | PRs #71/#73/#75 (manifest stuck at 0.11.4 across 4 bumps) |
| `services-iteration-grep` | Every chart template iterates services[] via `enabledServices` helper | PR #71 (deployment.yaml iterated raw `.Values.services`, broke disabled-service pods) |
| `dep-defaults-presence` | Every Helm dep in `Chart.yaml` has `<name>.enabled: false` default in `values.yaml` | PR #71 (redis dep added without default — loaded unconditionally) |
| `catalog-consistency` | `dsl-mappings.yaml` ↔ `rda-docs/reference/catalog.md` consistency (every chart in the YAML is listed in the doc's `## Catalogued charts` table) | (pre-existing) |
| `auth-seed` | binding-secret renders the auth-seed annotation when stateful | (pre-existing) |
| `auto-ingress-ui` | UI Ingress only when `ui.expose: true` | (pre-existing) |
| `passthrough-collision` | DSL field × passthrough field detect collisions | (pre-existing) |
| `dsl-mappings-schema` | `dsl-mappings.yaml` parses against the schema | (pre-existing) |
| `provisioning` | local / shared / external behaviour is consistent | (pre-existing) |
| `prometheus` | prometheus-specific projection invariants | (pre-existing) |
| `env-aliases` | env_aliases project the right additional env vars | (pre-existing) |

## When NOT to bump versions

- Documentation-only changes (this file, comments in templates,
  README typos) don't bump the version. Add the change as a
  `## MILESTONE: X.Y.Z+next` placeholder for the next behavior bump.
- Tests added for existing behavior (no new BEHAVIOR section) bump
  the version since they lock in an invariant — that IS a behavior
  change, even if subtle. Add a one-line MILESTONE entry.

## Adding a new chart to the catalogue

When you add a Helm dep (e.g. mariadb, kafka, mongodb), the workflow
spans 5 files in lockstep. The `dep-defaults-presence` test will
catch step 3 if you forget; nothing else is automated.

1. **`library-chart/Chart.yaml`** — append the dep with
   `condition: <chart>.enabled` and the AppCo OCI repository.
2. **`library-chart/values.yaml`** — add `<chart>: { enabled: false }`
   default block (with comments mirroring the other chart blocks).
3. **`library-chart/dsl-mappings.yaml`** — add the entry: `service.host`
   template (release-templated), `port`, `values_mapping` for DSL fields,
   `binding_secret` keys, optional `scaffold` defaults, optional
   `capabilities`, optional `dependencies`.
4. **`library-chart/SPEC.md`** — log the addition under the next
   MILESTONE block. Bump META.Version.
5. **`rda-bundle.yaml`** — bump `library_chart.version` AND append the
   chart's `type_name` under `service_catalog`.
6. **All template Chart.yaml** — bump the dep pin in every
   `templates/*/deploy/Chart.yaml`.
7. **`rda-docs/reference/catalog.md`** — add the chart row to the
   catalogued charts table.

No rda-cli change needed — the CLI auto-discovers from dsl-mappings.yaml.

### Extra steps for operator-managed charts

If the chart's workloads are created by a CRD operator (e.g. CNPG)
rather than directly by `helm template`:

8. **`operator_managed: true`** in the version entry, plus all companion
   fields: `operator_resource`, `cr_kind` (with `kind` + `api_version`),
   `pod_selector`, `cr_object`. The `operator-managed-consistency` test
   enforces completeness.
9. **Credential wiring** — if the operator auto-generates passwords,
   add a `derived_values` entry pointing the chart's credential secret
   reference to the binding secret (e.g. `cnpg.cluster.initdb.secret.name`
   → `{{ .Release.Name }}-{{ .Binding }}-binding`). Without this, the
   operator's password won't match the binding secret. The
   `cnpg-initdb-secret` test catches this for known charts.

## Anatomy of a good PR description

Mirror what `rda-cli` PRs do (look at recent merges for examples):

```markdown
## What changes

- Concrete list of behavior changes
- Cross-links to spec sections + tests

## Why

The user-visible problem this closes. Bonus: a specific bug discovered
live. Lessons go in SPEC.md LESSONS, not the PR body.

## Migration

What existing projects need to do (re-vendor, edit values, etc.).
Link to the relevant `rda upgrade` / Tilt-cache reset steps.

## Tests

What's been verified. List the bundle tests run + the e2e smoke if
applicable.
```
