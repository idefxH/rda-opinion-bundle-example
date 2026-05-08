# Project Templates

Each directory is a project template. Greenfield templates are scaffolded
by `rda new --template <id>`. Brownfield templates are scaffolded by
`rda init [--template <id>]`.

## Greenfield (rda new)

| Template | Language | Workload | HTTP? | Ingress? |
|----------|----------|----------|-------|----------|
| `web-go` | Go | Web server | Yes | Yes |
| `web-nodejs` | Node.js | Express server | Yes | Yes |
| `web-java` | Java 21 | HTTP server | Yes | Yes |
| `worker-go` | Go | Background worker | No | No |
| `worker-nodejs` | Node.js | Background worker | No | No |
| `worker-java` | Java 21 | Background worker | No | No |

## Brownfield (rda init)

| Template | Language | Build | Use case |
|----------|----------|-------|----------|
| `brownfield-generic` | auto-detect | pack build | Existing source code |
| `brownfield-image` | none | pre-built | Container image exists |
| `brownfield-helm` | none | none | Existing Helm chart |

Brownfield templates scaffold ONLY deployment files (deploy/, Tiltfile,
.rda/). They do NOT scaffold source code.

## Template structure

Each template contains:

```
<template>/
  template.yaml         ← metadata (id, language, description, placeholders)
  deploy/
    Chart.yaml           ← Helm chart with suse-library dependency
    values.yaml          ← default values with {{ .Name }} placeholders
    templates/.gitkeep
  Tiltfile               ← suse_app() call with {{ .ExtensionRef }}
  Procfile               ← CNB process types (web + dev)
  <source files>         ← language-specific (main.go, src/index.js, etc.)
```

## Placeholders

Templates use `{{ .Name }}`, `{{ .Language }}`, and `{{ .ExtensionRef }}`
placeholders that `rda new` substitutes at scaffold time.
