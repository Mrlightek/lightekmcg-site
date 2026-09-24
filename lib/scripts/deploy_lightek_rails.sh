#!/usr/bin/env bash
set -euo pipefail

[[ "${EUID}" -eq 0 ]] || { echo "ERROR: run as root"; exit 1; }

APP_USER="${APP_USER:-lightek}"
APP_NAME="${APP_NAME:-lightekmcg-site}"
APP_ROOT="${APP_ROOT:-/var/www/${APP_NAME}}"
RUBY_VERSION="${RUBY_VERSION:-3.3.6}"
APP_HOME="/home/${APP_USER}"
RBENV_ROOT="${APP_HOME}/.rbenv"
RUBY_BIN="${RBENV_ROOT}/versions/${RUBY_VERSION}/bin"
ENV_FILE="/etc/lightek/${APP_NAME}.env"

[[ -d "${APP_ROOT}/.git" ]] || { echo "ERROR: ${APP_ROOT} is not a Git checkout"; exit 1; }
[[ -f "${ENV_FILE}" ]] || { echo "ERROR: missing ${ENV_FILE}"; exit 1; }

echo "=== Pull ==="
git -C "${APP_ROOT}" pull --ff-only
chown -R "${APP_USER}:www-data" "${APP_ROOT}"

echo
echo "=== Bundle ==="
sudo -u "${APP_USER}" -H bash -lc "
  set -a
  source '${ENV_FILE}'
  set +a
  cd '${APP_ROOT}'
  '${RUBY_BIN}/bundle' config set --local without 'development test'
  '${RUBY_BIN}/bundle' config set --local deployment 'true'
  '${RUBY_BIN}/bundle' install --jobs 1
"

echo
echo "=== Database ==="
sudo -u "${APP_USER}" -H bash -lc "
  set -a
  source '${ENV_FILE}'
  set +a
  cd '${APP_ROOT}'
  '${RUBY_BIN}/bundle' exec rails db:migrate
"

echo
echo "=== Assets ==="
sudo -u "${APP_USER}" -H bash -lc "
  set -a
  source '${ENV_FILE}'
  set +a
  cd '${APP_ROOT}'
  '${RUBY_BIN}/bundle' exec rails assets:precompile
"

echo
echo "=== Restart ==="
systemctl restart "${APP_NAME}-sidekiq.service"
systemctl reload apache2

echo
echo "=== Status ==="
systemctl --no-pager --full status "${APP_NAME}-sidekiq.service" | head -20 || true
apache2ctl configtest
echo "Deploy complete."
