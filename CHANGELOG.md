# Changelog

## [0.13.0] - 2026-05-06

### Added

- Add `apache-airflow` to catalog (16 chart types total)
- Airflow dependencies: postgresql (`metadb`, required) + redis (`broker`, required)

### Changed

- Replace user-facing "DSL" terminology with "service schema/configuration"
- Update all CLI references to `rda service {add,rm,wire}` in READMEs, templates, values comments

## [0.12.0] - 2026-05-05

### Added

- Add multi-instance binding-secret host resolution via `_chart_aliases` map
- Add bundle test: `multi-instance-same-type` (binding-secret aliased hosts)
- Add `nodemon` to web-nodejs template (overlayfs-safe live-reload)

### Changed

- Bump tilt extension ref to `v0.4.0`
- Bump all template Chart.yaml to `0.12.0`
- Regenerate web-nodejs `package-lock.json` with nodemon

### Fixed

- Fix `_chart_aliases` scoping — use `$root.Values._chart_aliases` (sub-chart scope)
- Fix `CONTRIBUTING.md` — CLI is data-driven, no case statement needed to add a chart

## [0.11.38] - 2026-05-04

### Added

- Add 5 chart types: etcd, nats, opensearch, influxdb, harbor (15 total)
- Add 3 templates: web-java, worker-go, worker-java (6 total)
- Add cross-binding dependency wiring (dex → postgresql via `state_db`)
- Add CRD projection for routes
- Add sidecar injection support
- Add `operator` provisioning mode
- Add web template Redis cache status display

### Fixed

- Fix Java template "no default process" crash (add `heroku/procfile` buildpack)
- Fix Tilt privileged port remapping (ports <1024 → port+10000)

[0.13.0]: https://github.com/idefxH/rda-opinion-bundle-example/compare/v0.12.0...main
[0.12.0]: https://github.com/idefxH/rda-opinion-bundle-example/compare/v0.11.38...v0.12.0
[0.11.38]: https://github.com/idefxH/rda-opinion-bundle-example/releases/tag/v0.11.38
