# Multi-stage build using SUSE Application Collection Go images.
#
#   - dev variant: full Go SDK (toolchain, modules cache, tests). The
#     `-dev-` tag suffix marks AppCo's "with-SDK" flavour. Used for
#     compilation only.
#   - non-dev variant: slim runtime — Go binary, no toolchain. Smaller
#     image, smaller attack surface. The compiled binary is statically
#     linked CGO_ENABLED=0 so it runs without libc.
#
# When SUSE-AppCo buildpacks ship, this Dockerfile becomes optional —
# `pack build --builder registry.suse.com/rda/builder:latest` produces
# an equivalent image without a Dockerfile.

FROM dp.apps.rancher.io/containers/go:1.26.2-dev-8.1 AS build
WORKDIR /src
COPY go.mod ./
# Pre-warm the module cache. No go.sum yet (no deps); the COPY line
# stays tolerant of absence so first-time scaffolds don't fail.
COPY go.sum* ./
RUN go mod download
COPY . .
ENV CGO_ENABLED=0
RUN go build -trimpath -ldflags="-s -w" -o /out/app ./...

FROM dp.apps.rancher.io/containers/go:1.26.2-8.1
WORKDIR /app
COPY --from=build /out/app /app/app
EXPOSE 8080
USER 1000:1000
CMD ["/app/app"]
