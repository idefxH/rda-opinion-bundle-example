# {{ .Name }}

A Go web service scaffolded by `rda new <name> --template web-go`.

## What's inside

- `main.go` — net/http server with a single `GET /` route that
  reports liveness, readiness, and any postgres / mariadb binding
  discovered via the Kubernetes Service Binding Specification.
- `Dockerfile` — multi-stage build using SUSE Application Collection
  Go images: the `-dev-` variant for compilation, the slim variant for
  runtime. Static binary, CGO disabled, runs as UID 1000.
- `Tiltfile` — loads the `suse-rda` Tilt extension (auto-discovers
  port-forwards from `deploy/values.yaml`'s services[]).
- `deploy/` — Helm chart pinned to `suse-library` from the opinion
  bundle. `services[]` is the DSL surface for backing services.
- `Procfile` — CNB launch entries (`web` for prod, `dev` for inner-loop).

## Quick start

    rda doctor                                 # green-light your local cluster
    rda service add postgresql db              # append a postgres binding
    # edit deploy/values.yaml: fill the TODO: passwords, flip enabled: true
    tilt up                                    # build, deploy, port-forward

The `GET /` endpoint will then report the postgres binding it found
under `/bindings/db/` (host, port, database — credentials redacted).

## Database discovery

The example app discovers its database binding via env vars projected
by the rda library helper (`DB_HOST`, `DB_PORT`, `DB_USERNAME`,
`DB_PASSWORD`, `DB_DATABASE`). The binding name you pass to
`rda service add` becomes the env prefix (uppercase). Set
`DB_BINDING=<binding>` to override when multiple postgres bindings
exist.
