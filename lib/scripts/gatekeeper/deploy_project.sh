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

echo "[nav] Register dashboard control-plane navigation"
run_rails "bundle exec rails gatekeeper:dashboard_nav"

echo "[knowledge] Record known operational lessons"
run_rails "bundle exec rails gatekeeper:learn_dymond_dash_controller_contract" || echo "[knowledge] Lesson recording skipped; deployment continues"

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
HTTP_CODE=""
HEALTH_URL="https://${APP_DOMAIN}/up"
HEALTH_ATTEMPTS="${GATEKEEPER_HEALTH_ATTEMPTS:-12}"
HEALTH_SLEEP="${GATEKEEPER_HEALTH_SLEEP_SECONDS:-5}"
HEALTH_TIMEOUT="${GATEKEEPER_HEALTH_TIMEOUT_SECONDS:-10}"

for attempt in $(seq 1 "$HEALTH_ATTEMPTS"); do
  echo "Health check attempt ${attempt}/${HEALTH_ATTEMPTS}..."

  HTTP_CODE="$(
    curl -L -sS -o /dev/null -w '%{http_code}' \
      --max-time "$HEALTH_TIMEOUT" \
      "$HEALTH_URL" || true
  )"

  if [[ "$HTTP_CODE" == "200" ]]; then
    echo "Health check passed."
    break
  fi

  echo "Health check returned '${HTTP_CODE:-no response}'."
  if [[ "$attempt" -lt "$HEALTH_ATTEMPTS" ]]; then
    sleep "$HEALTH_SLEEP"
  fi
done

[[ "$HTTP_CODE" == "200" ]] || {
  echo "ERROR: healthcheck failed after ${HEALTH_ATTEMPTS} attempts"
  exit 1
}

SHA="$(git -C "${APP_ROOT}" rev-parse HEAD)"
echo "GATEKEEPER_DEPLOYED_SHA=${SHA}"
echo "GATEKEEPER_HTTP_STATUS=${HTTP_CODE}"
echo "DEPLOYMENT SUCCESSFUL"
