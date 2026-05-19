#!/usr/bin/env bash
# Install this repo's git hooks by pointing core.hooksPath at the
# versioned .githooks/ directory. Idempotent — safe to re-run.
#
# What you get after running this:
#   - .githooks/pre-commit fires on every `git commit`. When the
#     commit includes library-chart/Chart.yaml, it auto-aligns
#     rda-bundle.yaml and templates/*/deploy/Chart.yaml by running
#     scripts/bump-version.sh, then re-stages the touched files.
#
# Uninstall:    git config --unset core.hooksPath
# Bypass once:  RDA_SKIP_VERSION_HOOK=1 git commit ...   (or --no-verify)

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

if [ ! -d .githooks ]; then
  echo "install-hooks: no .githooks/ directory at repo root" >&2
  exit 1
fi

git config core.hooksPath .githooks

# Hooks must be executable; mode can drop on Windows checkouts or when
# files arrive via tarball. Setting it here is cheap and idempotent.
find .githooks -maxdepth 1 -type f -exec chmod +x {} \;

cat <<EOF
Installed git hooks from .githooks/
  core.hooksPath = $(git config --get core.hooksPath)

Active hooks:
$(ls -1 .githooks | sed 's/^/  - /')

The pre-commit hook auto-aligns the library-chart version across
rda-bundle.yaml and every templates/*/deploy/Chart.yaml whenever you
commit a library-chart/Chart.yaml version bump.

  Bypass:    RDA_SKIP_VERSION_HOOK=1 git commit ...   (or --no-verify)
  Uninstall: git config --unset core.hooksPath
EOF
