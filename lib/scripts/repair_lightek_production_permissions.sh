#!/usr/bin/env bash
set -euo pipefail

APP_ROOT="${APP_ROOT:-/var/www/lightekmcg-site}"
APP_USER="${APP_USER:-lightek}"
APP_GROUP="${APP_GROUP:-lightek}"
ENV_FILE="${ENV_FILE:-/etc/lightek/lightekmcg-site.env}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: run this script as root."
  exit 1
fi

[[ -d "$APP_ROOT" ]] || { echo "ERROR: app root not found: $APP_ROOT"; exit 1; }
[[ -f "$ENV_FILE" ]] || { echo "ERROR: env file not found: $ENV_FILE"; exit 1; }
id "$APP_USER" >/dev/null 2>&1 || { echo "ERROR: user not found: $APP_USER"; exit 1; }
getent group "$APP_GROUP" >/dev/null 2>&1 || { echo "ERROR: group not found: $APP_GROUP"; exit 1; }

echo "[1/5] Setting application ownership..."
chown -R "$APP_USER:$APP_GROUP" "$APP_ROOT"

echo "[2/5] Securing production environment..."
chown root:"$APP_GROUP" "$ENV_FILE"
chmod 640 "$ENV_FILE"

echo "[3/5] Ensuring Rails writable directories..."
install -d -o "$APP_USER" -g "$APP_GROUP" "$APP_ROOT/log"
install -d -o "$APP_USER" -g "$APP_GROUP" "$APP_ROOT/tmp"
install -d -o "$APP_USER" -g "$APP_GROUP" "$APP_ROOT/tmp/pids"
install -d -o "$APP_USER" -g "$APP_GROUP" "$APP_ROOT/tmp/cache"
install -d -o "$APP_USER" -g "$APP_GROUP" "$APP_ROOT/tmp/sockets"
install -d -o "$APP_USER" -g "$APP_GROUP" "$APP_ROOT/storage"

echo "[4/5] Verifying app user access..."
runuser -u "$APP_USER" -- test -r "$ENV_FILE"
runuser -u "$APP_USER" -- test -w "$APP_ROOT/db/schema.rb" 2>/dev/null || {
  if [[ -e "$APP_ROOT/db/schema.rb" ]]; then
    echo "ERROR: $APP_USER still cannot write db/schema.rb"
    exit 1
  fi
}

runuser -u "$APP_USER" -- test -w "$APP_ROOT/tmp"
runuser -u "$APP_USER" -- test -w "$APP_ROOT/log"

echo "[5/5] Ownership summary..."
stat -c '%U:%G %a %n' "$ENV_FILE"
stat -c '%U:%G %a %n' "$APP_ROOT"
[[ ! -e "$APP_ROOT/db/schema.rb" ]] || stat -c '%U:%G %a %n' "$APP_ROOT/db/schema.rb"

echo
echo "Production permissions repaired."
echo
echo "Expected model:"
echo "  $APP_ROOT -> $APP_USER:$APP_GROUP"
echo "  $ENV_FILE -> root:$APP_GROUP 640"
echo
echo "Re-run the failed GitHub Actions Deploy Production workflow."
