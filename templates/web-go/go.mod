module example.com/{{ .Name }}

// pgx v5.7+ requires go >= 1.23. We declare 1.24 to enable the
// `tool` directive (Go 1.24+) for managing dev-time tools like
// air without polluting the runtime require block. heroku/go
// fetches the requested Go version from go.dev/dl at build time.
go 1.24

require (
	github.com/jackc/pgx/v5 v5.7.6
	github.com/prometheus/client_golang v1.21.1
)

// Dev-time tool: air for live-reload during `tilt up`. `go tool air`
// resolves to the binary fetched into the module cache at
// `go mod tidy` time. The Procfile's dev process runs it.
tool github.com/air-verse/air

// Indirect deps. Pinned by go mod tidy on the rendered template — ship
// them here so the heroku/go buildpack's `go list -tags heroku` doesn't
// say "updates to go.mod needed; to update it: go mod tidy".
require (
	github.com/beorn7/perks v1.0.1 // indirect
	github.com/cespare/xxhash/v2 v2.3.0 // indirect
	github.com/jackc/pgpassfile v1.0.0 // indirect
	github.com/jackc/pgservicefile v0.0.0-20240606120523-5a60cdf6a761 // indirect
	github.com/jackc/puddle/v2 v2.2.2 // indirect
	github.com/klauspost/compress v1.17.11 // indirect
	github.com/munnerz/goautoneg v0.0.0-20191010083416-a7dc8b61c822 // indirect
	github.com/prometheus/client_model v0.6.1 // indirect
	github.com/prometheus/common v0.62.0 // indirect
	github.com/prometheus/procfs v0.15.1 // indirect
	golang.org/x/crypto v0.37.0 // indirect
	golang.org/x/sync v0.13.0 // indirect
	golang.org/x/sys v0.32.0 // indirect
	golang.org/x/text v0.24.0 // indirect
	google.golang.org/protobuf v1.36.1 // indirect
)
