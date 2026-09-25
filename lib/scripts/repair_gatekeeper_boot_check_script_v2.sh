#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

TARGET="lib/scripts/gatekeeper/check_application_boot.sh"

[[ -f config/application.rb ]] || {
  echo "ERROR: run this from the Rails app root"
  exit 1
}

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

RBENV_ROOT="/home/${APP_USER}/.rbenv"
RUBY_BIN="${RBENV_ROOT}/versions/${RUBY_VERSION}/bin"
RUNNER_FILE="/tmp/gatekeeper_boot_check_${$}.rb"

cleanup() {
  rm -f "$RUNNER_FILE"
}
trap cleanup EXIT

cat > "$RUNNER_FILE" <<'RUBY'
puts "Rails booted: #{Rails.version}"
puts "Environment: #{Rails.env}"
puts "DB: #{ActiveRecord::Base.connection.select_value('SELECT 1')}"
RUBY

chmod 644 "$RUNNER_FILE"

echo "=== ZEITWERK CHECK ==="

sudo -u "$APP_USER" -H \
  env -u GEM_HOME -u GEM_PATH \
  RBENV_ROOT="$RBENV_ROOT" \
  PATH="$RUBY_BIN:$RBENV_ROOT/bin:/usr/local/bin:/usr/bin:/bin" \
  ENV_FILE="$ENV_FILE" \
  APP_ROOT="$APP_ROOT" \
  bash -c '
    set -euo pipefail
    set -a
    source "$ENV_FILE"
    set +a
    cd "$APP_ROOT"
    bundle exec rails zeitwerk:check
  '

echo
echo "=== PRODUCTION BOOT CHECK ==="

sudo -u "$APP_USER" -H \
  env -u GEM_HOME -u GEM_PATH \
  RBENV_ROOT="$RBENV_ROOT" \
  PATH="$RUBY_BIN:$RBENV_ROOT/bin:/usr/local/bin:/usr/bin:/bin" \
  ENV_FILE="$ENV_FILE" \
  APP_ROOT="$APP_ROOT" \
  RUNNER_FILE="$RUNNER_FILE" \
  bash -c '
    set -euo pipefail
    set -a
    source "$ENV_FILE"
    set +a
    cd "$APP_ROOT"
    bundle exec rails runner "$RUNNER_FILE"
  '
BASH

chmod +x "$TARGET"

echo "=== SHELL SYNTAX ==="
bash -n "$TARGET"

echo
echo "=== GIT DIFF CHECK ==="
git diff --check -- "$TARGET"

echo
echo "Boot-check helper repaired successfully."
echo
echo "Optional local syntax verification:"
echo "  bash -n $TARGET"
echo
echo "Next:"
echo "  git add -A"
echo '  git commit -m "Repair Gatekeeper boot-check helper"'
echo "  git push origin main"
