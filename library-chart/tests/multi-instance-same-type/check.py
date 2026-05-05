#!/usr/bin/env python3
"""Multi-instance same-chart-type: verify that helm template renders
correctly when two services[] entries share a chart type and the
overlay uses aliased blocks + _chart_aliases.

Test:
  1. Two postgresql bindings (primary-db, events-db) produce TWO
     binding-secrets with distinct hosts.
  2. The hosts contain the alias (app-postgresql-primary-db, not app-postgresql).
  3. helm template exits 0 (no YAML errors).
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
        print("⚠ helm not on PATH — soft-skip")
        return 0

    with tempfile.TemporaryDirectory() as tmp:
        with open(os.path.join(tmp, "Chart.yaml"), "w") as f:
            f.write(textwrap.dedent(f"""\
                apiVersion: v2
                name: multi-inst-test
                version: 0.0.1
                dependencies:
                  - name: suse-library
                    repository: file://{LIBRARY}
                    version: ">=0"
                    alias: suse-library
            """))

        # values.yaml: two postgresql bindings with aliased overlay
        with open(os.path.join(tmp, "values.yaml"), "w") as f:
            f.write(textwrap.dedent("""\
                suse-library:
                  port: 8080
                  services:
                    - binding: primary-db
                      type: postgresql
                      enabled: true
                      auth:
                        user:
                          name: user1
                          password: pass1
                          database: db1
                        admin:
                          password: admin1
                    - binding: events-db
                      type: postgresql
                      enabled: true
                      auth:
                        user:
                          name: user2
                          password: pass2
                          database: db2
                        admin:
                          password: admin2
                  _chart_aliases:
                    primary-db: postgresql-primary-db
                    events-db: postgresql-events-db
                  postgresql-primary-db:
                    enabled: true
                    auth:
                      username: user1
                      password: pass1
                      database: db1
                      postgresPassword: admin1
                  postgresql-events-db:
                    enabled: true
                    auth:
                      username: user2
                      password: pass2
                      database: db2
                      postgresPassword: admin2
            """))

        os.makedirs(os.path.join(tmp, "templates"), exist_ok=True)
        with open(os.path.join(tmp, "templates", ".gitkeep"), "w") as f:
            pass

        r = subprocess.run(
            ["helm", "dependency", "update", tmp],
            capture_output=True, text=True
        )
        if r.returncode != 0:
            print(f"FAIL: helm dep update failed:\n{r.stderr}")
            return 1

        r = subprocess.run(
            ["helm", "template", "app", tmp,
             "--namespace", "test",
             "--values", os.path.join(tmp, "values.yaml")],
            capture_output=True, text=True
        )
        if r.returncode != 0:
            print(f"FAIL: helm template failed:\n{r.stderr}")
            return 1

        output = r.stdout

        # Check that two binding secrets exist
        primary_secret = "app-primary-db-binding" in output
        events_secret = "app-events-db-binding" in output
        if not primary_secret:
            print("FAIL: missing app-primary-db-binding secret")
            return 1
        if not events_secret:
            print("FAIL: missing app-events-db-binding secret")
            return 1

        # Check that hosts are aliased (contain the alias, not bare type)
        if "app-postgresql-primary-db" not in output:
            print("FAIL: binding-secret host should contain aliased name 'app-postgresql-primary-db'")
            print("(check _chart_aliases handling in _helpers.tpl)")
            return 1
        if "app-postgresql-events-db" not in output:
            print("FAIL: binding-secret host should contain aliased name 'app-postgresql-events-db'")
            return 1

        print("OK: multi-instance same-type renders correctly (2 binding-secrets, aliased hosts)")
        return 0


if __name__ == "__main__":
    sys.exit(main())
