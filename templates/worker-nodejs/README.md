# {{ .Name }}

A long-running background worker scaffolded by
`rda new <name> --template worker-nodejs`.

## What's inside

- `src/index.js` — heartbeat loop. Reads any binding under
  `$SERVICE_BINDING_ROOT` (default `/bindings`) and logs a tick
  every 10s. Replace with your real consumer (kafkajs, ioredis,
  amqplib, ...).
- `Dockerfile` — multi-stage Node.js build via SUSE BCI.
- `Tiltfile` — loads the `suse-rda` Tilt extension. No port-forward
  for the worker itself (no HTTP server); backing-service port-forwards
  are still auto-discovered from `deploy/values.yaml`.
- `deploy/values.yaml` — `ingress.enabled: false`, `service.enabled:
  false`, `probes.readiness: null`. The library chart renders the
  Deployment + binding-secret only.

## Quick start

    rda doctor                                 # green-light cluster
    rda service add apache-kafka events        # add a kafka binding
    # edit deploy/values.yaml: flip enabled: true
    tilt up                                    # build, deploy

`kubectl logs deploy/{{ .Name }} -f` shows the heartbeat. Each
binding mounted under `/bindings/` is logged at startup with its
type, host, and port.

## Why no HTTP server?

Workers exist to *consume* events / messages / cron triggers — they
don't accept inbound traffic. The library chart's Deployment shape is
the same as for web-* templates; only the Service + Ingress are
skipped, and the readinessProbe drops (no /ready endpoint to hit).
