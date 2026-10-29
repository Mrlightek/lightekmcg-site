#!/usr/bin/env bash
# Fresh Ubuntu 24.04 mail-node bootstrap for Lightek Mail.
# This deliberately installs only private services; it never opens SMTP to
# the Internet, enables customer sending or alters DNS without verification.
set -euo pipefail
cd "$(dirname "$0")/../.."
HOST="${LIGHTEK_MAIL_HOST:-mail.lightekmcg.com}"
DOMAIN="${LIGHTEK_MAIL_DKIM_DOMAIN:-lightekmcg.com}"
if [[ "${1:-}" != "--install" ]]; then
  echo "Usage: sudo LIGHTEK_MAIL_HOST=mail.lightekmcg.com LIGHTEK_MAIL_DKIM_DOMAIN=lightekmcg.com bash lib/scripts/setup_lightek_mail_node.sh --install"
  echo "Read-only audit and private configuration preview:"
  bash lib/scripts/audit_lightek_mail.sh
  python3 lib/scripts/lightek_mail_server.py plan --hostname "$HOST" --output "$(mktemp -d)"
  exit 0
fi
if [[ "$EUID" -ne 0 ]]; then echo "Run as root on a dedicated fresh Ubuntu 24.04 mail server." >&2; exit 1; fi
if [[ ! -f /etc/os-release ]] || ! grep -q '^VERSION_ID="24.04"' /etc/os-release || ! grep -q '^ID=ubuntu' /etc/os-release; then
  echo "This script requires Ubuntu 24.04." >&2; exit 1
fi
python3 lib/scripts/lightek_mail_server.py install --hostname "$HOST"
python3 lib/scripts/lightek_mail_server.py dkim --domain "$DOMAIN"
postfix check
rspamadm configtest
systemctl is-active --quiet postfix
systemctl is-active --quiet rspamd
systemctl is-active --quiet dovecot
systemctl is-active --quiet lightek-mail-redis
# Bootstrap a private mailbox on dedicated customer installations.
# The one-time credential remains root-only on the VPS, never in deployment logs.
if [[ -n "${LIGHTEK_MAIL_INITIAL_ADDRESS:-}" ]]; then
  SECRET_DIR=/etc/lightek
  SECRET_FILE="$SECRET_DIR/mail-initial-password"
  install -d -m 0700 "$SECRET_DIR"
  if [[ ! -e "$SECRET_FILE" ]]; then
    umask 077
    openssl rand -hex 32 > "$SECRET_FILE"
    chmod 0600 "$SECRET_FILE"
  fi
  python3 lib/scripts/lightek_mailbox.py --address "$LIGHTEK_MAIL_INITIAL_ADDRESS" --password-file "$SECRET_FILE"
fi
echo "LIGHTEK_MAIL_PRIVATE_NODE_READY"
echo "Outgoing mail remains HELD by design. To activate customer mail, configure recipient ingress, verified DNS/TLS/sender maps, test delivery and explicitly resume sending."
