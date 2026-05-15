# Scripts

| Script | Purpose |
|--------|---------|
| `sync-from-dsl-mappings.py` | Checks that Chart.yaml dependencies and values.yaml defaults are in sync with dsl-mappings.yaml. Auto-adds missing values.yaml defaults. |
| `chart-source.py` | Switches `Chart.yaml` between `appco` (default, includes OCI deps from the SUSE Application Collection) and `community` (strips those deps so `helm dep update` works without AppCo credentials). See below. |
| `appco-overlay.yaml` | The AppCo-only dependency blocks (postgresql, redis, mariadb, apache-kafka, valkey, etcd). Source of truth for `chart-source.py --mode appco`. Kept in sync with the AppCo block in `Chart.yaml`; `chart-source.py --check` enforces this. |

## chart-source.py

```bash
# Strip AppCo OCI deps from Chart.yaml (no creds required afterward):
python3 library-chart/scripts/chart-source.py --mode community

# Restore them from appco-overlay.yaml:
python3 library-chart/scripts/chart-source.py --mode appco

# Cleanest restore (preserves original ordering of dep blocks):
git checkout library-chart/Chart.yaml

# Verify the overlay file hasn't drifted from Chart.yaml:
python3 library-chart/scripts/chart-source.py --check
```

The bundle root also has thin bash wrappers for convenience:
`scripts/use-community-charts.sh`, `scripts/use-appco-charts.sh`.

Why this exists: `helm dep update` pulls every dep listed in
`Chart.yaml`, regardless of its `condition:` gate. AppCo OCI repos
need `helm registry login`. CI runs and community users have no such
credentials. Stripping the 6 AppCo-only deps lets the rest of the
catalog resolve from public Helm repos.
