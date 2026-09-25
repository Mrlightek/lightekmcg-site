#!/usr/bin/env bash
set -euo pipefail

: "${APP_ROOT:?APP_ROOT required}"
: "${APP_USER:?APP_USER required}"
: "${APP_NAME:?APP_NAME required}"
: "${APP_DOMAIN:?APP_DOMAIN required}"

APP_BRANCH="${APP_BRANCH:-main}"
RUBY_VERSION="${RUBY_VERSION:-3.3.6}"
APACHE_SERVICE="${APACHE_SERVICE:-apache2}"
SIDEKIQ_SERVICE="${SIDEKIQ_SERVICE:-${APP_NAME}-sidekiq}"
ENV_FILE="${ENV_FILE:-/etc/lightek/${APP_NAME}.env}"
RUBY_BIN="/home/${APP_USER}/.rbenv/versions/${RUBY_VERSION}/bin"

[[ "$EUID" -eq 0 ]] || { echo "ERROR: run as root"; exit 1; }
[[ -d "${APP_ROOT}/.git" ]] || { echo "ERROR: ${APP_ROOT} is not a git checkout"; exit 1; }
[[ -f "${ENV_FILE}" ]] || { echo "ERROR: missing ${ENV_FILE}"; exit 1; }

echo "[1/8] Pull"
git config --global --add safe.directory "${APP_ROOT}" >/dev/null 2>&1 || true
git -C "${APP_ROOT}" fetch origin "${APP_BRANCH}"
git -C "${APP_ROOT}" checkout "${APP_BRANCH}"
git -C "${APP_ROOT}" pull --ff-only origin "${APP_BRANCH}"

run_rails() {
  sudo -u "${APP_USER}" -H env -u GEM_HOME -u GEM_PATH bash -lc "
    set -a
    source '${ENV_FILE}'
    set +a
    export RBENV_ROOT='/home/${APP_USER}/.rbenv'
    export PATH='${RUBY_BIN}:/home/${APP_USER}/.rbenv/bin:/usr/local/bin:/usr/bin:/bin'
    cd '${APP_ROOT}'
    $*
  "
}

echo "[2/8] Bundle"
run_rails "bundle install --jobs 1"

echo "[3/8] Migrate"
run_rails "bundle exec rails db:migrate"

echo "[4/8] Assets"
run_rails "bundle exec rails assets:precompile"

echo "[5/8] Zeitwerk / boot validation"
run_rails "bundle exec rails zeitwerk:check"

echo "[6/8] Sidekiq"
systemctl restart "${SIDEKIQ_SERVICE}"
systemctl is-active --quiet "${SIDEKIQ_SERVICE}"

echo "[7/8] Apache"
apache2ctl configtest
systemctl reload "${APACHE_SERVICE}"
systemctl is-active --quiet "${APACHE_SERVICE}"

echo "[8/8] Health"
HTTP_CODE="$(curl -L -sS -o /dev/null -w '%{http_code}' --max-time 20 "https://${APP_DOMAIN}/up")"
[[ "$HTTP_CODE" == "200" ]] || { echo "ERROR: healthcheck HTTP ${HTTP_CODE}"; exit 1; }

SHA="$(git -C "${APP_ROOT}" rev-parse HEAD)"
echo "GATEKEEPER_DEPLOYED_SHA=${SHA}"
echo "GATEKEEPER_HTTP_STATUS=${HTTP_CODE}"
echo "DEPLOYMENT SUCCESSFUL"
