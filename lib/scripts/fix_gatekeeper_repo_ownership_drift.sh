#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

DEPLOY="lib/scripts/gatekeeper/deploy_project.sh"
WORKFLOW=".github/workflows/deploy-production.yml"

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/gatekeeper_repo_ownership_${STAMP}"

mkdir -p "$BACKUP"

for file in "$DEPLOY" "$WORKFLOW"; do
  [[ -f "$file" ]] || {
    echo "ERROR: missing $file"
    exit 1
  }

  mkdir -p "$BACKUP/$(dirname "$file")"
  cp "$file" "$BACKUP/$file"
done

echo "==> Fixing Gatekeeper Git ownership model"

python3 <<'PY'
from pathlib import Path

path = Path("lib/scripts/gatekeeper/deploy_project.sh")
src = path.read_text()

old = '''echo "[1/8] Pull"
git config --global --add safe.directory "${APP_ROOT}" >/dev/null 2>&1 || true
git -C "${APP_ROOT}" fetch origin "${APP_BRANCH}"
git -C "${APP_ROOT}" checkout "${APP_BRANCH}"
git -C "${APP_ROOT}" pull --ff-only origin "${APP_BRANCH}"
'''

new = '''echo "[1/8] Pull"

run_as_app_user() {
  sudo -u "${APP_USER}" -H env -u GEM_HOME -u GEM_PATH bash -lc "
    export RBENV_ROOT='/home/${APP_USER}/.rbenv'
    export PATH='${RUBY_BIN}:/home/${APP_USER}/.rbenv/bin:/usr/local/bin:/usr/bin:/bin'
    cd '${APP_ROOT}'
    $*
  "
}

run_as_app_user "git fetch origin '${APP_BRANCH}'"
run_as_app_user "git checkout '${APP_BRANCH}'"
run_as_app_user "git pull --ff-only origin '${APP_BRANCH}'"
'''

if new in src:
    print("Gatekeeper Git operations already run as APP_USER.")
elif old in src:
    path.write_text(src.replace(old, new, 1))
    print("Gatekeeper Git operations now run as APP_USER.")
else:
    raise SystemExit(
        "ERROR: expected Gatekeeper pull block not found; no deploy-script changes written."
    )
PY

echo "==> Removing root bootstrap pull from GitHub Actions"

python3 <<'PY'
from pathlib import Path

path = Path(".github/workflows/deploy-production.yml")
src = path.read_text()

old = '''            cd /var/www/lightekmcg-site

            git fetch origin main
            git checkout main
            git pull --ff-only origin main

            APP_ROOT=/var/www/lightekmcg-site \\
'''

new = '''            APP_ROOT=/var/www/lightekmcg-site \\
'''

if old in src:
    src = src.replace(old, new, 1)
    path.write_text(src)
    print("Removed duplicate root Git bootstrap from workflow.")
elif "git pull --ff-only origin main" not in src:
    print("Workflow root bootstrap pull already absent.")
else:
    raise SystemExit(
        "ERROR: Git bootstrap exists but expected block did not match; no workflow changes written."
    )
PY

echo
echo "=== SHELL SYNTAX ==="
bash -n "$DEPLOY"

echo
echo "=== WORKFLOW CHECK ==="
if grep -nE '^[[:space:]]+git (fetch|checkout|pull)' "$WORKFLOW"; then
  echo "ERROR: workflow still contains direct production Git operations"
  exit 1
else
  echo "Workflow contains no direct production Git pull."
fi

echo
echo "=== GATEKEEPER GIT CHECK ==="
grep -n -A18 -B3 \
  'run_as_app_user\|git fetch\|git checkout\|git pull' \
  "$DEPLOY"

echo
echo "=== DIFF CHECK ==="
git diff --check

echo
echo "=== TARGETED DIFF ==="
git --no-pager diff -- \
  "$DEPLOY" \
  "$WORKFLOW"

echo
echo "=== STATUS ==="
git status --short

echo
echo "GATEKEEPER REPOSITORY OWNERSHIP FIX COMPLETE"
echo "Backup: $BACKUP"
