#!/usr/bin/env bash
set -euo pipefail

: "${APP_ROOT:?APP_ROOT required}"
: "${APP_USER:?APP_USER required}"
: "${APP_NAME:?APP_NAME required}"
: "${APP_DOMAIN:?APP_DOMAIN required}"
[[ "$APP_DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]] || { echo "ERROR: APP_DOMAIN must be a DNS hostname"; exit 1; }

APP_BRANCH="${APP_BRANCH:-main}"
RUBY_VERSION="${RUBY_VERSION:-3.3.6}"
APACHE_SERVICE="${APACHE_SERVICE:-apache2}"
SIDEKIQ_SERVICE="${SIDEKIQ_SERVICE:-${APP_NAME}-sidekiq}"
ENV_FILE="${ENV_FILE:-/etc/lightek/${APP_NAME}.env}"
RUBY_BIN="/home/${APP_USER}/.rbenv/versions/${RUBY_VERSION}/bin"

[[ "$EUID" -eq 0 ]] || { echo "ERROR: run as root"; exit 1; }
[[ -d "${APP_ROOT}/.git" ]] || { echo "ERROR: ${APP_ROOT} is not a git checkout"; exit 1; }
[[ -f "${ENV_FILE}" ]] || { echo "ERROR: missing ${ENV_FILE}"; exit 1; }

# Share the native fleet adapter's checkout lock with ordinary deployments.
FLEET_LOCK_KEY="$(printf '%s' "$(readlink -f "$APP_ROOT")" | sha256sum | cut -c1-24)"
install -d -m 0700 "/var/lib/lightek/fleet/${FLEET_LOCK_KEY}"
exec 9>"/var/lib/lightek/fleet/${FLEET_LOCK_KEY}/update.lock"
flock -n 9 || { echo "ERROR: another deployment owns this checkout"; exit 1; }

echo "[1/8] Pull"

run_as_app_user() {
  sudo -u "${APP_USER}" -H env -u GEM_HOME -u GEM_PATH bash -lc "
    export RBENV_ROOT='/home/${APP_USER}/.rbenv'
    export PATH='${RUBY_BIN}:/home/${APP_USER}/.rbenv/bin:/usr/local/bin:/usr/bin:/bin'
    cd '${APP_ROOT}'
    $*
  "
}

run_as_app_user "bash lib/scripts/gatekeeper/prepare_checkout.sh '${APP_ROOT}'"

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

echo "[studio] Install and verify Blender media dependency"
python3 "${APP_ROOT}/lib/scripts/setup_studio_docker_access.py" --app-user "$APP_USER"
run_rails "bash lib/scripts/setup_studio_media.sh"

python3 "${APP_ROOT}/lib/scripts/setup_studio_spatial.py" --app-root "$APP_ROOT" --app-user "$APP_USER" --domain "$APP_DOMAIN" --env-file "$ENV_FILE"

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
if [[ -f "${APP_ROOT}/lib/scripts/gatekeeper/${SIDEKIQ_SERVICE}.service" ]]; then
  cp "${APP_ROOT}/lib/scripts/gatekeeper/${SIDEKIQ_SERVICE}.service" "/etc/systemd/system/${SIDEKIQ_SERVICE}.service"
  systemctl daemon-reload
  systemctl enable "${SIDEKIQ_SERVICE}"
fi
systemctl restart "${SIDEKIQ_SERVICE}"
systemctl is-active --quiet "${SIDEKIQ_SERVICE}"

echo "[cable] Refresh installed standalone WebSocket backend"
if systemctl cat "${APP_NAME}-cable.service" >/dev/null 2>&1; then
  systemctl restart "${APP_NAME}-cable.service"
  systemctl is-active --quiet "${APP_NAME}-cable.service"
  python3 "${APP_ROOT}/lib/scripts/lightek_cable_setup.py" --probe-backend
fi

echo "[studio] Queue native Blender starter files"
run_rails "LIGHTEK_STUDIO_SITE_HOST='${APP_DOMAIN}' bundle exec rails studio:blender:bootstrap"

echo "[7/8] Apache"
apache2ctl configtest
systemctl reload "${APACHE_SERVICE}"
systemctl is-active --quiet "${APACHE_SERVICE}"
# Apache reload can retire Passenger's control socket while this CLI connects.
# Fall back to Passenger's restart marker; the health gate below still has to pass.
if ! passenger-config restart-app "${APP_ROOT}" --ignore-app-not-running; then
  echo "Passenger control command failed; requesting application restart through tmp/restart.txt"
  run_as_app_user "mkdir -p tmp && touch tmp/restart.txt"
fi

# Activate the new repair UI before enforcing this gate on legacy installations.
# A failed binding never receives deployment acceptance; an operator can repair
# the existing row from the dashboard and rerun verification.
echo "[website] Verify the release domain and PWA binding"
run_rails "LIGHTEK_EXPECTED_SITE_HOST='${APP_DOMAIN}' bundle exec rails lightek:site_binding:verify"

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
