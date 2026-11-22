#!/usr/bin/env bash
set -euo pipefail

: "${APP_ROOT:?APP_ROOT required}"
: "${APP_DOMAIN:?APP_DOMAIN required}"

APACHE_SERVICE="${APACHE_SERVICE:-apache2}"
SIDEKIQ_SERVICE="${SIDEKIQ_SERVICE:-}"
FAILED=0

systemctl is-active --quiet "$APACHE_SERVICE" && echo "OK apache" || { echo "FAIL apache"; FAILED=1; }

PASSENGER_STATUS="$(passenger-status 2>/dev/null)" &&
  grep -Fq -- "$APP_ROOT" <<< "$PASSENGER_STATUS" && echo "OK passenger" || { echo "FAIL passenger"; FAILED=1; }

HTTP_CODE="$(curl -L -sS -o /dev/null -w '%{http_code}' --max-time 20 "https://${APP_DOMAIN}/up" || true)"
[[ "$HTTP_CODE" == "200" ]] && echo "OK https 200" || { echo "FAIL https ${HTTP_CODE}"; FAILED=1; }

recover_failed_worker() (
  [[ "${EXPECTED_WORKER_RELEASE:-}" =~ ^[a-f0-9]{40}$ ]] || exit 1
  [[ "$SIDEKIQ_SERVICE" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.@-]*$ ]] || exit 1
  local lock_key lock_dir checkout
  checkout="$(readlink -f "$APP_ROOT")" || exit 1
  lock_key="$(printf '%s' "$checkout" | sha256sum | cut -c1-24)" || exit 1
  lock_dir="/var/lib/lightek/fleet/${lock_key}"
  install -d -m 0700 "$lock_dir" || exit 1
  exec 9>"$lock_dir/update.lock" || exit 1
  flock -n 9 || exit 1
  [[ "$(git -c safe.directory="$checkout" -C "$checkout" rev-parse HEAD)" == "$EXPECTED_WORKER_RELEASE" ]] || exit 1
  # An intentionally stopped unit reports inactive. Only restart a failed unit.
  systemctl is-failed --quiet "$SIDEKIQ_SERVICE" || exit 1
  systemctl is-active --quiet "$APACHE_SERVICE" || exit 1
  local locked_status
  locked_status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 "https://${APP_DOMAIN}/up")" || exit 1
  [[ "$locked_status" == "200" ]] || exit 1
  systemctl start "$SIDEKIQ_SERVICE" && systemctl is-active --quiet "$SIDEKIQ_SERVICE" || exit 1
  locked_status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 20 "https://${APP_DOMAIN}/up")" || exit 1
  [[ "$locked_status" == "200" ]] || exit 1
  echo "GATEKEEPER_WORKER_RECOVERED=1"
)

if [[ -n "$SIDEKIQ_SERVICE" ]]; then
  if ! systemctl is-active --quiet "$SIDEKIQ_SERVICE"; then
    if [[ "$FAILED" -eq 0 ]] && recover_failed_worker; then
      echo "OK sidekiq (recovered)"
    else
      echo "FAIL sidekiq"
      FAILED=1
    fi
  else
    echo "OK sidekiq"
  fi
fi

exit "$FAILED"
