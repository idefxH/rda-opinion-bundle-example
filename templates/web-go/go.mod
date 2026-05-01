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
//
// Two groups:
//   - pgx + prom transitives (unconditional runtime deps)
//   - air's transitives (only used by the dev tool — pulled in via the
//     `tool` directive above, but Go's module graph requires them in
//     go.mod since the tool directive participates in module resolution)
require (
	dario.cat/mergo v1.0.2 // indirect
	github.com/air-verse/air v1.65.1 // indirect
	github.com/andybalholm/brotli v1.2.0 // indirect
	github.com/beorn7/perks v1.0.1 // indirect
	github.com/bep/godartsass/v2 v2.5.0 // indirect
	github.com/bep/golibsass v1.2.0 // indirect
	github.com/cespare/xxhash/v2 v2.3.0 // indirect
	github.com/fatih/color v1.18.0 // indirect
	github.com/fsnotify/fsnotify v1.9.0 // indirect
	github.com/gobwas/glob v0.2.3 // indirect
	github.com/gohugoio/hugo v0.149.1 // indirect
	github.com/jackc/pgpassfile v1.0.0 // indirect
	github.com/jackc/pgservicefile v0.0.0-20240606120523-5a60cdf6a761 // indirect
	github.com/jackc/puddle/v2 v2.2.2 // indirect
	github.com/joho/godotenv v1.5.1 // indirect
	github.com/klauspost/compress v1.17.11 // indirect
	github.com/mattn/go-colorable v0.1.14 // indirect
	github.com/mattn/go-isatty v0.0.20 // indirect
	github.com/munnerz/goautoneg v0.0.0-20191010083416-a7dc8b61c822 // indirect
	github.com/pelletier/go-toml v1.9.5 // indirect
	github.com/pelletier/go-toml/v2 v2.2.4 // indirect
	github.com/prometheus/client_model v0.6.1 // indirect
	github.com/prometheus/common v0.62.0 // indirect
	github.com/prometheus/procfs v0.15.1 // indirect
	github.com/spf13/afero v1.14.0 // indirect
	github.com/spf13/cast v1.9.2 // indirect
	github.com/tdewolff/parse/v2 v2.8.3 // indirect
	golang.org/x/crypto v0.41.0 // indirect
	golang.org/x/sync v0.16.0 // indirect
	golang.org/x/sys v0.35.0 // indirect
	golang.org/x/text v0.28.0 // indirect
	google.golang.org/protobuf v1.36.8 // indirect
)
