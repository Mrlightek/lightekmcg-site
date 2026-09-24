#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-lightekmcg-site}"
ENV_FILE="${ENV_FILE:-/etc/lightek/lightekmcg-site.env}"
OVERRIDE_DIR="/etc/systemd/system/apache2.service.d"
OVERRIDE_FILE="${OVERRIDE_DIR}/${APP_NAME}.conf"

[[ "${EUID}" -eq 0 ]] || { echo "ERROR: run as root"; exit 1; }
[[ -f "${ENV_FILE}" ]] || { echo "ERROR: missing ${ENV_FILE}"; exit 1; }

mkdir -p "${OVERRIDE_DIR}"

cat > "${OVERRIDE_FILE}" <<EOF
[Service]
EnvironmentFile=${ENV_FILE}
EOF

chmod 644 "${OVERRIDE_FILE}"

systemctl daemon-reload

echo "=== APACHE ENV OVERRIDE ==="
cat "${OVERRIDE_FILE}"

echo
echo "=== APACHE CONFIG ==="
apache2ctl configtest

echo
echo "=== PASSENGER RUBY IN VHOST ==="
grep -n "PassengerRuby" "/etc/apache2/sites-available/${APP_NAME}.conf"

echo
echo "Prepared Apache/Passenger environment."
echo "Apache has NOT been started."
