#!/usr/bin/env bash
set -euo pipefail

: "${APP_ROOT:?APP_ROOT required}"
: "${APP_DOMAIN:?APP_DOMAIN required}"

APACHE_SERVICE="${APACHE_SERVICE:-apache2}"
SIDEKIQ_SERVICE="${SIDEKIQ_SERVICE:-}"
FAILED=0

systemctl is-active --quiet "$APACHE_SERVICE" && echo "OK apache" || { echo "FAIL apache"; FAILED=1; }

if [[ -n "$SIDEKIQ_SERVICE" ]]; then
  systemctl is-active --quiet "$SIDEKIQ_SERVICE" && echo "OK sidekiq" || { echo "FAIL sidekiq"; FAILED=1; }
fi

passenger-status 2>/dev/null | grep -Fq "$APP_ROOT" && echo "OK passenger" || { echo "FAIL passenger"; FAILED=1; }

HTTP_CODE="$(curl -L -sS -o /dev/null -w '%{http_code}' --max-time 20 "https://${APP_DOMAIN}/up" || true)"
[[ "$HTTP_CODE" == "200" ]] && echo "OK https 200" || { echo "FAIL https ${HTTP_CODE}"; FAILED=1; }

exit "$FAILED"
