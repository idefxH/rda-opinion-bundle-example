#!/usr/bin/env python3
"""
Validate library-chart/dsl-mappings.yaml against the v1alpha1 schema.

Catches malformed entries BEFORE helm template fails with a confusing
template error. Designed to run in CI and in `library-chart/tests/`.

Schema (mirrors the file's own header documentation):

  apiVersion: rda.suse.com/dsl-mapping/v1alpha1
  charts:
    <chart-name>:
      versions:
        - constraint:        <semver constraint>
          service:
            host:            <go template>
            port:            <int>
            scheme:          <string, optional>
          values_mapping:    <dict[str,str]>
          binding_secret:    <list of dicts>
            - key:           <string>
              literal:       <string>          # exclusive
              template:      <string>          # exclusive
              from_dsl:      <string>          # exclusive (with required, default)
              required:      <bool>            # only with from_dsl
              default:       <string>          # only with from_dsl
              skip_env:      <bool>            # optional
              env_aliases:   <list of strings> # optional; emits additional
                                               # env vars referencing the
                                               # same Secret key

Exit codes:
  0  schema valid
  1  schema invalid (errors printed to stderr)
"""
import os
import sys

# Lazy import; PyYAML is universal but absent on minimal CI containers.
try:
    import yaml
except ImportError:
    sys.stderr.write("PyYAML not installed; pip3 install pyyaml or use python3 -m pip install pyyaml\n")
    sys.exit(2)

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MAPPING_FILE = os.path.join(REPO_ROOT, "dsl-mappings.yaml")
EXPECTED_API_VERSION = "rda.suse.com/dsl-mapping/v1alpha1"

# Used to validate that values_mapping target paths start with the chart name —
# guarantees collision detection in validatePassthrough computes the right
# sub-path (it strips the chart-name prefix).
RESERVED_BS_KEYS = {"key", "literal", "template", "from_dsl",
                    "required", "default", "skip_env", "env_aliases"}


def err(errors, path, msg):
    errors.append("%s: %s" % (path, msg))


def check_binding_secret(errors, chart, vidx, bs):
    if not isinstance(bs, list):
        err(errors, "charts.%s.versions[%d].binding_secret" % (chart, vidx),
            "must be a list, got %s" % type(bs).__name__)
        return
    seen_keys = set()
    for ei, entry in enumerate(bs):
        path = "charts.%s.versions[%d].binding_secret[%d]" % (chart, vidx, ei)
        if not isinstance(entry, dict):
            err(errors, path, "must be a map, got %s" % type(entry).__name__)
            continue
        # Reject unknown fields — typo guard.
        unknown = set(entry.keys()) - RESERVED_BS_KEYS
        if unknown:
            err(errors, path, "unknown fields: %s. Allowed: %s" %
                (sorted(unknown), sorted(RESERVED_BS_KEYS)))
        if "key" not in entry:
            err(errors, path, "missing 'key'")
            continue
        key = entry["key"]
        if not isinstance(key, str) or not key:
            err(errors, path, "key must be a non-empty string")
            continue
        if key in seen_keys:
            err(errors, path, "duplicate key %r" % key)
        seen_keys.add(key)
        # Exactly one of {literal, template, from_dsl}
        sources = [k for k in ("literal", "template", "from_dsl") if k in entry]
        if len(sources) != 1:
            err(errors, "%s.key=%s" % (path, key),
                "must have exactly one of {literal, template, from_dsl}, got %s" %
                (sources or "none"))
        # required/default only meaningful with from_dsl
        if "from_dsl" not in entry:
            for k in ("required", "default"):
                if k in entry:
                    err(errors, "%s.key=%s" % (path, key),
                        "%s only allowed when from_dsl is set" % k)
        if "required" in entry and not isinstance(entry["required"], bool):
            err(errors, "%s.key=%s" % (path, key),
                "required must be bool")
        if "skip_env" in entry and not isinstance(entry["skip_env"], bool):
            err(errors, "%s.key=%s" % (path, key),
                "skip_env must be bool")
        if "env_aliases" in entry:
            aliases = entry["env_aliases"]
            if not isinstance(aliases, list):
                err(errors, "%s.key=%s" % (path, key),
                    "env_aliases must be a list of strings, got %s" %
                    type(aliases).__name__)
            else:
                for ai, a in enumerate(aliases):
                    if not isinstance(a, str) or not a:
                        err(errors, "%s.key=%s.env_aliases[%d]" % (path, key, ai),
                            "must be a non-empty string")
                # An alias that re-spells the secret key as itself is
                # a no-op; flag the typo. snakecase comparison covers
                # camelCase / kebab-case equivalence.
                import re
                norm = lambda s: re.sub(r"[\W_]+", "", s.lower())
                key_norm = norm(key)
                for ai, a in enumerate(aliases):
                    if isinstance(a, str) and norm(a) == key_norm:
                        err(errors, "%s.key=%s.env_aliases[%d]" % (path, key, ai),
                            "alias %r resolves to the same env-var name as the "
                            "key %r — drop it (it would emit a duplicate env "
                            "var entry on the Deployment)." % (a, key))
        if "skip_env" in entry and entry.get("skip_env") and "env_aliases" in entry:
            err(errors, "%s.key=%s" % (path, key),
                "env_aliases on a skip_env entry is meaningless — the "
                "primary env var is suppressed, so the aliases would be "
                "the only env vars projected. Either drop skip_env or "
                "drop env_aliases.")


def check_values_mapping(errors, chart, vidx, vm):
    if not isinstance(vm, dict):
        err(errors, "charts.%s.versions[%d].values_mapping" % (chart, vidx),
            "must be a dict, got %s" % type(vm).__name__)
        return
    prefix = chart + "."
    for dsl_path, values_path in vm.items():
        path = "charts.%s.versions[%d].values_mapping[%s]" % (chart, vidx, dsl_path)
        if not isinstance(values_path, str):
            err(errors, path, "value must be a string, got %s" %
                type(values_path).__name__)
            continue
        # validatePassthrough strips this prefix to derive the passthrough
        # sub-path. Without it, collision detection would falsely match
        # against the chart-level values key.
        if not values_path.startswith(prefix):
            err(errors, path,
                "value %r should start with chart name prefix %r so passthrough "
                "collision detection extracts the right sub-path. Either add the "
                "prefix or document the deviation." % (values_path, prefix))


def check_service(errors, chart, vidx, svc):
    if not isinstance(svc, dict):
        err(errors, "charts.%s.versions[%d].service" % (chart, vidx),
            "must be a dict, got %s" % type(svc).__name__)
        return
    if "host" not in svc:
        err(errors, "charts.%s.versions[%d].service" % (chart, vidx),
            "missing 'host' (Go template)")
    elif not isinstance(svc["host"], str) or not svc["host"]:
        err(errors, "charts.%s.versions[%d].service.host" % (chart, vidx),
            "must be a non-empty string")
    if "port" not in svc:
        err(errors, "charts.%s.versions[%d].service" % (chart, vidx),
            "missing 'port'")
    elif not isinstance(svc["port"], int):
        err(errors, "charts.%s.versions[%d].service.port" % (chart, vidx),
            "must be an integer, got %s" % type(svc["port"]).__name__)


def check_version(errors, chart, vidx, ver):
    base = "charts.%s.versions[%d]" % (chart, vidx)
    if not isinstance(ver, dict):
        err(errors, base, "must be a dict")
        return
    for required in ("constraint", "service", "values_mapping", "binding_secret"):
        if required not in ver:
            err(errors, base, "missing required field %r" % required)
    constraint = ver.get("constraint")
    if constraint is not None and (not isinstance(constraint, str) or not constraint):
        err(errors, base + ".constraint", "must be a non-empty semver constraint string")
    if "service" in ver:
        check_service(errors, chart, vidx, ver["service"])
    if "values_mapping" in ver:
        check_values_mapping(errors, chart, vidx, ver["values_mapping"])
    if "binding_secret" in ver:
        check_binding_secret(errors, chart, vidx, ver["binding_secret"])


def check_chart(errors, chart, body):
    base = "charts.%s" % chart
    if not isinstance(body, dict):
        err(errors, base, "must be a dict")
        return
    versions = body.get("versions")
    if not isinstance(versions, list) or not versions:
        err(errors, base + ".versions", "must be a non-empty list")
        return
    for vidx, ver in enumerate(versions):
        check_version(errors, chart, vidx, ver)


def main():
    if not os.path.isfile(MAPPING_FILE):
        print("ERROR: %s not found" % MAPPING_FILE, file=sys.stderr)
        return 1
    with open(MAPPING_FILE) as f:
        try:
            doc = yaml.safe_load(f)
        except yaml.YAMLError as e:
            print("ERROR: %s: parse error: %s" % (MAPPING_FILE, e), file=sys.stderr)
            return 1

    errors = []
    if not isinstance(doc, dict):
        err(errors, "<root>", "must be a dict")
    else:
        api = doc.get("apiVersion")
        if api != EXPECTED_API_VERSION:
            err(errors, "apiVersion",
                "expected %r, got %r" % (EXPECTED_API_VERSION, api))
        charts = doc.get("charts")
        if not isinstance(charts, dict) or not charts:
            err(errors, "charts", "must be a non-empty dict of chart-name -> chart-block")
        else:
            for chart, body in charts.items():
                check_chart(errors, chart, body)

    if errors:
        print("✗ dsl-mappings.yaml schema invalid:", file=sys.stderr)
        for e in errors:
            print("  - " + e, file=sys.stderr)
        print("", file=sys.stderr)
        print("%d error(s)." % len(errors), file=sys.stderr)
        return 1

    chart_count = len(doc.get("charts") or {})
    print("✓ dsl-mappings.yaml schema valid (%d chart(s) catalogued)" % chart_count)
    return 0


if __name__ == "__main__":
    sys.exit(main())
