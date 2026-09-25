#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

[[ -f config/application.rb ]] || { echo "ERROR: run from Rails app root"; exit 1; }

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/gatekeeper_zeitwerk_fix_${STAMP}"
mkdir -p "$BACKUP"

backup() {
  local f="$1"
  if [[ -f "$f" ]]; then
    mkdir -p "$BACKUP/$(dirname "$f")"
    cp "$f" "$BACKUP/$f"
  fi
}

FILES=(
  app/services/gatekeeper/github_actions_service.rb
  app/controllers/gatekeeper/projects_controller.rb
  lib/scripts/install_gatekeeper_github_cicd.sh
  lib/scripts/gatekeeper/deploy_project.sh
)

for f in "${FILES[@]}"; do
  backup "$f"
done

python3 - <<'PY'
from pathlib import Path

targets = [
    Path("app/services/gatekeeper/github_actions_service.rb"),
    Path("app/controllers/gatekeeper/projects_controller.rb"),
    Path("lib/scripts/install_gatekeeper_github_cicd.sh"),
]

for path in targets:
    if not path.exists():
        continue
    text = path.read_text()
    text = text.replace("GitHubActionsService", "GithubActionsService")
    path.write_text(text)
    print(f"Patched Zeitwerk constant naming in {path}")
PY

python3 - <<'PY'
from pathlib import Path

path = Path("lib/scripts/gatekeeper/deploy_project.sh")
if not path.exists():
    raise SystemExit("ERROR: deploy script not found")

text = path.read_text()

if "[5/8] Zeitwerk / boot validation" not in text:
    replacements = [
        ('echo "[1/7] Pull"', 'echo "[1/8] Pull"'),
        ('echo "[2/7] Bundle"', 'echo "[2/8] Bundle"'),
        ('echo "[3/7] Migrate"', 'echo "[3/8] Migrate"'),
        ('echo "[4/7] Assets"', 'echo "[4/8] Assets"'),
        ('echo "[5/7] Sidekiq"', 'echo "[5/8] Zeitwerk / boot validation"\nrun_rails "bundle exec rails zeitwerk:check"\n\necho "[6/8] Sidekiq"'),
        ('echo "[6/7] Apache"', 'echo "[7/8] Apache"'),
        ('echo "[7/7] Health"', 'echo "[8/8] Health"'),
    ]
    for old, new in replacements:
        if old not in text:
            raise SystemExit(f"ERROR: expected marker missing from deploy script: {old}")
        text = text.replace(old, new, 1)

    path.write_text(text)
    print("Added Zeitwerk pre-restart validation to deploy script.")
else:
    print("Deploy script already contains Zeitwerk validation.")
PY

cat > lib/scripts/gatekeeper/check_application_boot.sh <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="${APP_ROOT:-/var/www/lightekmcg-site}"
APP_USER="${APP_USER:-lightek}"
APP_NAME="${APP_NAME:-lightekmcg-site}"
RUBY_VERSION="${RUBY_VERSION:-3.3.6}"
ENV_FILE="${ENV_FILE:-/etc/lightek/${APP_NAME}.env}"
RUBY_BIN="/home/${APP_USER}/.rbenv/versions/${RUBY_VERSION}/bin"

sudo -u "${APP_USER}" -H env -u GEM_HOME -u GEM_PATH bash -lc "
  set -a
  source '${ENV_FILE}'
  set +a
  export RBENV_ROOT='/home/${APP_USER}/.rbenv'
  export PATH='${RUBY_BIN}:/home/${APP_USER}/.rbenv/bin:/usr/local/bin:/usr/bin:/bin'
  cd '${APP_ROOT}'

  echo '=== ZEITWERK CHECK ==='
  bundle exec rails zeitwerk:check

  echo
  echo '=== PRODUCTION BOOT CHECK ==='
  bundle exec rails runner '
    puts "Rails booted: #{Rails.version}"
    puts "Environment: #{Rails.env}"
    puts "DB: #{ActiveRecord::Base.connection.select_value(%q{SELECT 1})}"
  '
"
BASH

chmod +x lib/scripts/gatekeeper/check_application_boot.sh

echo
echo "=== RUBY SYNTAX ==="
ruby -c app/services/gatekeeper/github_actions_service.rb
ruby -c app/controllers/gatekeeper/projects_controller.rb

echo
echo "=== SHELL SYNTAX ==="
bash -n lib/scripts/gatekeeper/deploy_project.sh
bash -n lib/scripts/gatekeeper/check_application_boot.sh

echo
echo "=== VERIFY CONSTANT NAME ==="
grep -R -n   -e 'GitHubActionsService'   -e 'GithubActionsService'   app config lib || true

echo
echo "=== GIT DIFF CHECK ==="
git diff --check

echo
echo "Patch complete."
echo "Backup: $BACKUP"
echo
echo "Next:"
echo "  bin/rails zeitwerk:check"
echo "  git add -A"
echo '  git commit -m "Fix Gatekeeper Zeitwerk naming and add boot validation"'
echo "  git push origin main"
