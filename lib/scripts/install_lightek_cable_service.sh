#!/usr/bin/env bash
set -euo pipefail
APP_ROOT="${APP_ROOT:-/var/www/lightekmcg-site}"
exec python3 "${APP_ROOT}/lib/scripts/lightek_cable_setup.py" "$@"
