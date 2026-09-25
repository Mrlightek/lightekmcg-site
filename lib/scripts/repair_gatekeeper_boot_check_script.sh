#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

TARGET="lib/scripts/gatekeeper/check_application_boot.sh"

[[ -f config/application.rb ]] || { echo "ERROR: run from Rails app root"; exit 1; }

STAMP="$(date +%Y%m%d%H%M%S)"
if [[ -f "$TARGET" ]]; then
  cp "$TARGET" "${TARGET}.backup.${STAMP}"
fi

mkdir -p "$(dirname "$TARGET")"

cat > "$TARGET" <<'BASH'
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
  bundle exec rails runner \\"puts %{Rails booted: #{Rails.version}}; puts %{Environment: #{Rails.env}}; puts %{DB: #{ActiveRecord::Base.connection.select_value(%q{SELECT 1})}}\\"
"
BASH

chmod +x "$TARGET"

echo "=== SHELL SYNTAX ==="
bash -n "$TARGET"

echo
echo "=== CONTENT ==="
cat -n "$TARGET"

echo
echo "=== GIT DIFF CHECK ==="
git diff --check -- "$TARGET"

echo
echo "Boot-check script repaired."
echo
echo "Next:"
echo "  bin/rails zeitwerk:check"
echo "  git add $TARGET lib/scripts/fix_gatekeeper_zeitwerk_and_boot_pipeline.sh app/services/gatekeeper/github_actions_service.rb app/controllers/gatekeeper/projects_controller.rb lib/scripts/install_gatekeeper_github_cicd.sh lib/scripts/gatekeeper/deploy_project.sh"
echo '  git commit -m "Fix Gatekeeper Zeitwerk naming and boot validation"'
echo "  git push origin main"
