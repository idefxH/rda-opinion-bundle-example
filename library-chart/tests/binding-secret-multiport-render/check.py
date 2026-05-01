#!/usr/bin/env python3
"""Regression: binding-secret.yaml renders valid YAML for multi-port
charts (dex, minio, ...) and combinations thereof.

Why this test exists: the helper's multi-port emission section had
right-trim `-}}` on the per-iteration assignments, which stripped the
trailing newline + indent. The first multi-port key (e.g. `http_host`)
landed at column 0 instead of column 2, gluing onto the previous
line's value:

    issuer: "http://app-dex:5556"http_host: "..."
                                ^^^ glued, YAML parse fails
                                    line 25: did not find expected key

For postgresql (single-port, no `service.ports` block) the code path
was skipped; the bug only fired when at least one of the enabled
bindings declared `service.ports` in dsl-mappings.yaml. This made the
e2e suite's single-binding scenarios pass while combined ones blew up.

Discovered live: scenario 15-fullstack-postgres-dex-liveupdate failed
its first `helm template` step on every run with the multi-port path
indentation bug.

Test guard: render the bundled example chart with a values overlay
that activates BOTH a single-port (postgresql) and a multi-port (dex)
binding, then run `helm template` and verify:
  1. helm template exit=0
  2. the rendered binding-secret YAML parses as valid YAML
  3. no `<port_name>_host:` key has lost its 2-space indent
"""
import os
import shutil
import subprocess
import sys
import tempfile
import textwrap

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
LIBRARY = os.path.join(REPO_ROOT)


def have(cmd):
    return shutil.which(cmd) is not None


def main():
    if not have("helm"):
        print("⚠ helm not on PATH — soft-skip (test runs in CI w/ helm)")
        return 0

    with tempfile.TemporaryDirectory() as tmp:
        # Mini-chart that depends on the local library-chart.
        with open(os.path.join(tmp, "Chart.yaml"), "w") as f:
            f.write(textwrap.dedent(f"""\
                apiVersion: v2
                name: bsec-multiport-test
                version: 0.0.1
                dependencies:
                  - name: suse-library
                    repository: file://{LIBRARY}
                    version: ~0
            """))
        # Values: BOTH single-port (postgresql) and multi-port (dex).
        with open(os.path.join(tmp, "values.yaml"), "w") as f:
            f.write(textwrap.dedent("""\
                suse-library:
                  name: app
                  port: 8080
                  image:
                    repository: app
                    tag: dev
                  imagePullSecrets:
                    - name: application-collection
                  services:
                    - binding: db
                      type: postgresql
                      enabled: true
                      auth:
                        admin: { password: "x" }
                        user: { password: "y", database: "z" }
                    - binding: auth
                      type: dex
                      enabled: true
                      issuer: "http://app-dex.app.svc.cluster.local:5556"
                      passthrough:
                        config:
                          enablePasswordDB: true
                          oauth2: { skipApprovalScreen: true }
                          staticClients: []
                          staticPasswords: []
                          storage: { type: memory }
            """))
        # helm dep update — pulls the local library-chart into charts/.
        try:
            subprocess.run(
                ["helm", "dependency", "update", tmp],
                check=True, capture_output=True, text=True,
            )
        except subprocess.CalledProcessError as e:
            print("✗ helm dependency update failed:", file=sys.stderr)
            print(e.stderr, file=sys.stderr)
            return 1

        # Render binding-secret only.
        proc = subprocess.run(
            [
                "helm", "template", "test", tmp,
                "--namespace", "test",
                "--show-only", "charts/suse-library/templates/binding-secret.yaml",
            ],
            capture_output=True, text=True,
        )
        if proc.returncode != 0:
            print("✗ helm template failed — binding-secret render is broken", file=sys.stderr)
            print("--- stderr ---", file=sys.stderr)
            print(proc.stderr, file=sys.stderr)
            print("--- stdout ---", file=sys.stderr)
            print(proc.stdout, file=sys.stderr)
            return 1

        rendered = proc.stdout

        # 1. Parse as valid YAML.
        try:
            import yaml
        except ImportError:
            print("⚠ PyYAML not available — soft-skip parse check (CI has it)")
            return 0

        try:
            docs = list(yaml.safe_load_all(rendered))
        except yaml.YAMLError as e:
            print("✗ rendered binding-secret.yaml is not valid YAML:", file=sys.stderr)
            print(f"  {e}", file=sys.stderr)
            print("--- rendered (first 60 lines) ---", file=sys.stderr)
            for line in rendered.splitlines()[:60]:
                print(f"  {line}", file=sys.stderr)
            return 1

        # 2. Indentation check: every multi-port `_host` / `_port` / `_url`
        #    key in the rendered output must be indented by exactly 2 spaces
        #    (i.e. live under `stringData:`). A mis-indented key would have
        #    been glued to the previous line — caught above by yaml.safe_load
        #    — but we add this explicit check so the failure message points
        #    at the regression directly.
        bad_indent = []
        for ln, line in enumerate(rendered.splitlines(), 1):
            stripped = line.lstrip()
            for suffix in ("_host:", "_port:", "_url:"):
                if stripped.startswith(("http", "grpc", "s3", "console", "tcp")) and suffix in stripped[:50]:
                    indent = len(line) - len(stripped)
                    if indent != 2:
                        bad_indent.append((ln, indent, line))
        if bad_indent:
            print("✗ multi-port keys have wrong indentation (expected 2 spaces under stringData:):", file=sys.stderr)
            for ln, ind, line in bad_indent:
                print(f"  line {ln}: indent={ind} → {line!r}", file=sys.stderr)
            return 1

        # 3. Sanity: at least 2 Secrets emitted (db + auth).
        secrets = [d for d in docs if d and d.get("kind") == "Secret"]
        if len(secrets) < 2:
            print(f"✗ expected ≥2 Secret docs, got {len(secrets)}", file=sys.stderr)
            return 1

        # 4. Sanity: the auth (dex) Secret has both `port` (primary) and
        #    `http_port` / `grpc_port` (per-port).
        auth = next((s for s in secrets if "auth-binding" in s["metadata"]["name"]), None)
        if not auth:
            print("✗ no auth-binding Secret in render", file=sys.stderr)
            return 1
        sd = auth.get("stringData", {})
        for required in ("host", "port", "url", "issuer", "http_host", "http_port", "http_url",
                         "grpc_host", "grpc_port", "grpc_url"):
            if required not in sd:
                print(f"✗ auth Secret missing key: {required}", file=sys.stderr)
                print("    keys present:", sorted(sd.keys()), file=sys.stderr)
                return 1

        n = len(rendered.splitlines())
        print(f"✓ binding-secret-multiport-render: {len(secrets)} Secrets, {n} lines, all keys indented + parseable.")
        return 0


if __name__ == "__main__":
    sys.exit(main())
