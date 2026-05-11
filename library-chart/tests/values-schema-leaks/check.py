"""
values-schema-leaks: detect library chart defaults that would produce
fields the sub-chart doesn't expect.

The dangerous pattern: library-chart/values.yaml has a leaf like
`postgresql.persistence.size: 1Gi`, but dsl-mappings maps
`persistence.size` → `postgresql.persistence.resources.requests.storage`.
When Helm merges these, the sub-chart sees BOTH `.Values.persistence.size`
(from library defaults) AND `.Values.persistence.resources.requests.storage`
(from the render engine overlay). Charts using `render.values` or `toYaml`
on the parent dump everything — producing invalid K8s resources.

The test flags a library default leaf path when:
1. It matches a DSL field name (e.g. `persistence.size`)
2. The DSL maps that field to a DIFFERENT sub-chart path
3. They share a common parent (both under `persistence`)

This catches the write-to-same-subtree collision without false-flagging
independent fields (like `metrics.enabled` which lives outside the
mapped subtree).
"""

import sys
import yaml
from pathlib import Path

HERE = Path(__file__).parent
LIB = HERE.parent.parent

def load_yaml(path):
    with open(path) as f:
        return yaml.safe_load(f)

def leaf_paths(d, prefix=""):
    if isinstance(d, dict):
        for k, v in d.items():
            p = f"{prefix}.{k}" if prefix else k
            yield from leaf_paths(v, p)
    elif isinstance(d, list):
        pass
    else:
        yield prefix

def common_prefix(a, b):
    pa = a.split(".")
    pb = b.split(".")
    common = []
    for x, y in zip(pa, pb):
        if x == y:
            common.append(x)
        else:
            break
    return ".".join(common)

def main():
    mappings = load_yaml(LIB / "dsl-mappings.yaml")
    values = load_yaml(LIB / "values.yaml")

    charts = mappings.get("charts", {})
    errors = []

    for chart_type, chart_data in charts.items():
        versions = chart_data.get("versions", [])
        if not versions:
            continue
        ver = versions[0]
        vm = ver.get("values_mapping", {})

        alias = chart_data.get("chart_alias", chart_type)
        chart_defaults = values.get(alias, {})
        if not isinstance(chart_defaults, dict):
            continue

        default_leaves = set(leaf_paths(chart_defaults))

        for dsl_path, chart_target in vm.items():
            prefix = alias + "."
            if not chart_target.startswith(prefix):
                continue
            subchart_target = chart_target[len(prefix):]

            if dsl_path not in default_leaves:
                continue
            if dsl_path == subchart_target:
                continue

            cp = common_prefix(dsl_path, subchart_target)
            if not cp:
                continue

            errors.append(
                f"  {alias}: default '{dsl_path}' collides with mapping "
                f"target '{subchart_target}' (shared parent: {cp})"
            )

    if errors:
        print("FAIL: library chart defaults collide with mapping targets:")
        for e in errors:
            print(e)
        return 1

    print("OK: no colliding default fields detected")
    return 0

if __name__ == "__main__":
    sys.exit(main())
