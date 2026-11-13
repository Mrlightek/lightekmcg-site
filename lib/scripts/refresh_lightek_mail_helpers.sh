#!/usr/bin/env bash
# Refresh only an already-installed Lightek receiving integration. No listener,
# firewall, DNS, credential or daemon configuration is changed by this update.
set -euo pipefail
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNTIME_DIR=/usr/local/lib/lightek-mail
if ! command -v systemctl >/dev/null || ! systemctl cat lightek-mail-recipient-sync.service >/dev/null 2>&1; then
  echo 'LIGHTEK_MAIL_HELPERS_SKIPPED receiving integration is not installed'
  exit 0
fi
[[ "$EUID" -eq 0 ]] || { echo 'Existing mail integration updates require the deployment operator.' >&2; exit 1; }
[[ -d "$RUNTIME_DIR" && ! -L "$RUNTIME_DIR" ]] || { echo 'Unexpected managed mail runtime directory.' >&2; exit 1; }
for script in lightek_mail_ingress.py fetch_lightek_mail_routes.py lightek_mail_route_maps.py sync_lightek_mail_recipients.sh; do
  [[ -f "$SOURCE_DIR/$script" && ! -L "$RUNTIME_DIR/$script" ]] || { echo 'Unexpected managed mail helper path.' >&2; exit 1; }
  install -o root -g root -m 0644 "$SOURCE_DIR/$script" "$RUNTIME_DIR/$script"
done
echo 'LIGHTEK_MAIL_HELPERS_REFRESHED existing timer applies mailbox routes automatically'
