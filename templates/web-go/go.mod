module example.com/{{ .Name }}

// pgx v5.7+ requires go >= 1.23; the heroku/go buildpack respects
// this directive when picking the Go toolchain to install.
go 1.23

require (
	github.com/jackc/pgx/v5 v5.7.6
	github.com/prometheus/client_golang v1.21.1
)
