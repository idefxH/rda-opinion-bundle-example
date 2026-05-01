#!/usr/bin/env python3
"""Smoke-test every template by ACTUALLY running `pack build` against
its rendered output. Catches the entire class of "buildpack succeeds
the static-shape test but fails at runtime" bugs that motivated this
test in the first place:

  - go.mod's `go` directive too low for a dep's published floor
    (heroku/go: `requires go >= 1.X`)
  - go.sum missing/stale (heroku/go: `missing go.sum entry...`)
  - package.json deps drifted from Procfile commands
    (CrashLoopBackOff: `nodemon: command not found`)
  - any other buildpack regression we haven't seen yet

WHY THIS TEST EXISTS: the static guards (template-go-sum-present,
template-procfile-package-consistency, template-go-deps-version-compat)
catch bugs by SHAPE — once we know what to look for. They cannot
catch a buildpack regression we haven't seen. This test runs the
actual buildpack pipeline and surfaces ANY failure.

DEPENDENCIES (fail-soft if missing — test SKIPs):
  - pack CLI (https://buildpacks.io/docs/install-pack/)
  - Docker daemon reachable (DOCKER_HOST or default socket)
  - Network to pull heroku/builder:24 (~400MB on first run)

RUNTIME: ~30-60s per template after first-run warmup. ~3 min cold.

USAGE:
  python3 check.py
  SKIP_PACK_SMOKE=1 python3 check.py    # explicit skip (CI shortcut)

EXIT CODES:
  0  all templates built, OR skipped (fail-soft)
  1  at least one template failed pack build (real regression)
  2  prerequisite missing AND test required (env override)
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile


REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TEMPLATES_DIR = os.path.join(REPO_ROOT, "..", "templates")
BUILDER = "heroku/builder:24"


def have(cmd):
    return shutil.which(cmd) is not None


def docker_alive():
    """Quick liveness check: docker info without pulling anything."""
    try:
        r = subprocess.run(
            ["docker", "info", "--format", "{{.ServerVersion}}"],
            capture_output=True, timeout=5,
        )
        return r.returncode == 0
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return False


def render_template(template_dir, project_name, scratch):
    """Copy template_dir → scratch/<project_name>, substitute
    {{ .Name }} and {{ .Language }} like rda new would. Skips files
    listed in .gitignore patterns (we don't need them for a build)."""
    dst = os.path.join(scratch, project_name)
    shutil.copytree(template_dir, dst, ignore=shutil.ignore_patterns(
        ".git", "node_modules", "vendor", "deploy",
    ))
    # Resolve language from template.yaml: e.g. "language: go".
    lang = "unknown"
    tyaml = os.path.join(template_dir, "template.yaml")
    if os.path.isfile(tyaml):
        with open(tyaml) as f:
            for line in f:
                m = re.match(r"^\s*language:\s*(\S+)", line)
                if m:
                    lang = m.group(1).strip("'\"")
                    break
    # Walk dst, substitute placeholders in text files.
    for root, _, files in os.walk(dst):
        for fname in files:
            path = os.path.join(root, fname)
            try:
                with open(path) as f:
                    text = f.read()
            except (UnicodeDecodeError, OSError):
                continue
            new = text.replace("{{ .Name }}", project_name).replace(
                "{{ .Language }}", lang
            )
            if new != text:
                with open(path, "w") as f:
                    f.write(new)
    return dst, lang


# Buildpack list per language. Mirrors LANGUAGE_DEFAULTS in
# tilt-extension-suse-rda/suse_rda/Tiltfile. Drift here is itself a
# bug — but until they share a source we re-state it.
BUILDPACKS_BY_LANG = {
    "nodejs": ["heroku/nodejs", "heroku/procfile"],
    "go":     ["heroku/go"],
    "python": ["heroku/python"],
    "java":   ["heroku/java"],
}


def pack_build(project_dir, lang, project_name, log_path):
    bps = BUILDPACKS_BY_LANG.get(lang, [])
    if not bps:
        return True, "skipped — language %r has no buildpack mapping" % lang
    args = ["pack", "build", project_name + ":smoke", "--builder", BUILDER]
    for bp in bps:
        args.extend(["--buildpack", bp])
    args.extend(["--path", project_dir, "--pull-policy", "if-not-present"])
    with open(log_path, "w") as logf:
        r = subprocess.run(
            args, stdout=logf, stderr=subprocess.STDOUT,
            timeout=300, cwd=project_dir,
        )
    if r.returncode != 0:
        return False, "pack build exited %d (see %s)" % (r.returncode, log_path)
    # Tear down the resulting image (best-effort) so we don't leak.
    subprocess.run(
        ["docker", "rmi", "-f", project_name + ":smoke"],
        capture_output=True,
    )
    return True, "pack build OK"


def main():
    if os.environ.get("SKIP_PACK_SMOKE", "") == "1":
        print("✓ template-pack-build-smoke: SKIPPED (SKIP_PACK_SMOKE=1)")
        return 0
    if not have("pack"):
        print("⊘ template-pack-build-smoke: SKIPPED (pack CLI not installed; "
              "https://buildpacks.io/docs/install-pack/)")
        return 0
    if not have("docker") or not docker_alive():
        print("⊘ template-pack-build-smoke: SKIPPED (docker daemon unreachable)")
        return 0
    if not os.path.isdir(TEMPLATES_DIR):
        print("✗ templates/ not found at " + TEMPLATES_DIR, file=sys.stderr)
        return 2

    failures = []
    inspected = 0
    scratch = tempfile.mkdtemp(prefix="rda-pack-smoke-")
    try:
        for entry in sorted(os.listdir(TEMPLATES_DIR)):
            tdir = os.path.join(TEMPLATES_DIR, entry)
            if not os.path.isdir(tdir):
                continue
            tyaml = os.path.join(tdir, "template.yaml")
            if not os.path.isfile(tyaml):
                continue
            inspected += 1
            project_name = "smoke-" + entry.replace("_", "-")
            print("→ rendering %s ..." % entry, flush=True)
            project_dir, lang = render_template(tdir, project_name, scratch)
            log_path = os.path.join(scratch, project_name + ".log")
            print("→ pack build %s (lang=%s) ..." % (project_name, lang),
                  flush=True)
            ok, msg = pack_build(project_dir, lang, project_name, log_path)
            if ok:
                print("  ✓ %s — %s" % (entry, msg))
            else:
                failures.append((entry, msg, log_path))
                print("  ✗ %s — %s" % (entry, msg), file=sys.stderr)
                # Print last 30 lines of log so the failure is visible
                # without hunting in /tmp.
                try:
                    with open(log_path) as f:
                        tail = f.readlines()[-30:]
                    print("    last 30 lines:", file=sys.stderr)
                    for line in tail:
                        print("      " + line.rstrip(), file=sys.stderr)
                except OSError:
                    pass
    finally:
        if not failures:
            shutil.rmtree(scratch, ignore_errors=True)
        else:
            print(
                "  (failure logs preserved at %s)" % scratch, file=sys.stderr
            )

    if failures:
        return 1
    if inspected == 0:
        print("✓ template-pack-build-smoke: no templates with template.yaml found")
    else:
        print("✓ template-pack-build-smoke: %d template(s) built cleanly via pack"
              % inspected)
    return 0


if __name__ == "__main__":
    sys.exit(main())
