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
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
src = path.read_text()

replacement = '''      - name: Deploy production
        id: deploy
        shell: bash
        env:
          SSH_HOST: ${{ secrets.PRODUCTION_HOST }}
          SSH_USER: ${{ secrets.PRODUCTION_USER }}
          SSH_PORT: ${{ secrets.PRODUCTION_SSH_PORT }}
        run: |
          set -euo pipefail
          PORT="${SSH_PORT:-22}"

          ssh -i ~/.ssh/lightek_deploy -p "$PORT" -o BatchMode=yes "$SSH_USER@$SSH_HOST" '
            set -e

            cd /var/www/lightekmcg-site

            git fetch origin main
            git checkout main
            git pull --ff-only origin main

            APP_ROOT=/var/www/lightekmcg-site \\
            APP_USER=lightek \\
            APP_NAME=lightekmcg-site \\
            APP_DOMAIN=lightekmcg.com \\
            APP_BRANCH=main \\
            RUBY_VERSION=3.3.6 \\
            APACHE_SERVICE=apache2 \\
            SIDEKIQ_SERVICE=lightekmcg-site-sidekiq \\
            ENV_FILE=/etc/lightek/lightekmcg-site.env \\
            bash /var/www/lightekmcg-site/lib/scripts/gatekeeper/deploy_project.sh
          ' | tee deploy-output.txt

          DEPLOYED_SHA="$(grep '^GATEKEEPER_DEPLOYED_SHA=' deploy-output.txt | tail -1 | cut -d= -f2-)"
          HTTP_STATUS="$(grep '^GATEKEEPER_HTTP_STATUS=' deploy-output.txt | tail -1 | cut -d= -f2-)"

          echo "deployed_sha=$DEPLOYED_SHA" >> "$GITHUB_OUTPUT"
          echo "http_status=$HTTP_STATUS" >> "$GITHUB_OUTPUT"

'''

pattern = re.compile(r'(?ms)^      - name: Deploy production\n.*?(?=^      - name: |\Z)')
match = pattern.search(src)

if not match:
    print("ERROR: could not find a step named exactly: Deploy production")
    print()
    print("Steps found:")
    for m in re.finditer(r'(?m)^\s*-\s+name:\s*(.+)$', src):
        print("  -", m.group(1))
    sys.exit(2)

old = match.group(0)

if "git pull --ff-only origin main" in old and "bash /var/www/lightekmcg-site/lib/scripts/gatekeeper/deploy_project.sh" in old:
    print("Workflow is already patched; no change needed.")
    sys.exit(0)

src = src[:match.start()] + replacement + src[match.end():]
path.write_text(src)

print("Replaced the entire Deploy production step.")
PY

echo
echo "=== DEPLOY STEP NOW ==="
python3 - "$WORKFLOW" <<'PY'
import re
import sys
from pathlib import Path
src = Path(sys.argv[1]).read_text()
m = re.search(r'(?ms)^      - name: Deploy production\n.*?(?=^      - name: |\Z)', src)
print(m.group(0) if m else "ERROR: deploy step missing")
PY

echo
echo "=== REQUIRED LINES ==="
grep -q 'git fetch origin main' "$WORKFLOW"
grep -q 'git pull --ff-only origin main' "$WORKFLOW"
grep -q 'bash /var/www/lightekmcg-site/lib/scripts/gatekeeper/deploy_project.sh' "$WORKFLOW"

git diff --check -- "$WORKFLOW"

echo
echo "Patch complete."
echo "Backup:"
echo "  $BACKUP"
echo
echo "Next:"
echo "  git add $WORKFLOW"
echo '  git commit -m "Bootstrap production pull before Gatekeeper deploy script"'
echo "  git push origin main"
