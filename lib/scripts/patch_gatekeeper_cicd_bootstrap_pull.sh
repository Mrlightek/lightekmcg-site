#!/usr/bin/env bash
set -euo pipefail

WORKFLOW="${1:-.github/workflows/deploy-production.yml}"

if [[ ! -f "$WORKFLOW" ]]; then
  echo "ERROR: workflow not found: $WORKFLOW"
  exit 1
fi

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="${WORKFLOW}.backup.${STAMP}"
cp "$WORKFLOW" "$BACKUP"

python3 - "$WORKFLOW" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
src = path.read_text()

old = '''          ssh -i ~/.ssh/lightek_deploy -p "$PORT" -o BatchMode=yes "$SSH_USER@$SSH_HOST" \
            "APP_ROOT='$APP_ROOT' APP_USER='$APP_USER' APP_NAME='$APP_NAME' APP_DOMAIN='$APP_DOMAIN' APP_BRANCH='$APP_BRANCH' RUBY_VERSION='$RUBY_VERSION' APACHE_SERVICE='$APACHE_SERVICE' SIDEKIQ_SERVICE='$SIDEKIQ_SERVICE' ENV_FILE='$ENV_FILE' bash '$APP_ROOT/lib/scripts/gatekeeper/deploy_project.sh'" \
            | tee deploy-output.txt
'''

new = '''          ssh -i ~/.ssh/lightek_deploy -p "$PORT" -o BatchMode=yes "$SSH_USER@$SSH_HOST" '
            set -e

            cd /var/www/lightekmcg-site

            git fetch origin main
            git checkout main
            git pull --ff-only origin main

            APP_ROOT=/var/www/lightekmcg-site \
            APP_USER=lightek \
            APP_NAME=lightekmcg-site \
            APP_DOMAIN=lightekmcg.com \
            APP_BRANCH=main \
            RUBY_VERSION=3.3.6 \
            APACHE_SERVICE=apache2 \
            SIDEKIQ_SERVICE=lightekmcg-site-sidekiq \
            ENV_FILE=/etc/lightek/lightekmcg-site.env \
            bash /var/www/lightekmcg-site/lib/scripts/gatekeeper/deploy_project.sh
          ' | tee deploy-output.txt
'''

if new in src:
    print("Workflow already patched; no change needed.")
    sys.exit(0)

if old not in src:
    print("ERROR: expected Deploy production SSH block was not found.")
    print("No changes were written.")
    sys.exit(2)

path.write_text(src.replace(old, new, 1))
print("Patched Deploy production step with bootstrap git pull.")
PY

echo
echo "=== VERIFY PATCH ==="
grep -n -A30 -B5 'name: Deploy production' "$WORKFLOW" || true

echo
echo "=== CHECK REQUIRED LINES ==="
grep -q 'git fetch origin main' "$WORKFLOW"
grep -q 'git pull --ff-only origin main' "$WORKFLOW"
grep -q 'bash /var/www/lightekmcg-site/lib/scripts/gatekeeper/deploy_project.sh' "$WORKFLOW"

git diff --check -- "$WORKFLOW"

echo
echo "Done."
echo "Backup:"
echo "  $BACKUP"
echo
echo "Next:"
echo "  git add $WORKFLOW"
echo '  git commit -m "Bootstrap production pull before Gatekeeper deploy script"'
echo "  git push origin main"
