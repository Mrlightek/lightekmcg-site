#!/usr/bin/env bash
# Connect the central Postfix virtual mailbox maps to Rails webmail.
# Run on the central host where both Postfix and the production Rails app live.
set -euo pipefail
APP_DIR="${LIGHTEK_APP_DIR:-/var/www/lightekmcg-site}"
MAP=/etc/postfix/lightek_transports
if [[ "${1:-}" != --apply ]]; then
  echo "Usage: sudo LIGHTEK_APP_DIR=/var/www/lightekmcg-site bash lib/scripts/activate_lightek_mail_receiving.sh --apply [--listen-public]"
  echo "Installs exact-recipient HTTPS routing and a mailbox sync timer. --listen-public additionally opens the Postfix listener on all interfaces (requires a restart)."
  exit 0
fi
[[ "$EUID" -eq 0 ]] || { echo 'Run as root on the central mail host.' >&2; exit 1; }
[[ -z "${2:-}" || "${2:-}" == --listen-public ]] || exit 1
[[ "$APP_DIR" =~ ^/[a-zA-Z0-9_./-]+$ ]]
[[ "${LIGHTEK_ENV_FILE:-/etc/lightek/lightekmcg-site.env}" =~ ^/[a-zA-Z0-9_./-]+$ ]]
[[ -f "$APP_DIR/config/environment.rb" && -f "$APP_DIR/lib/scripts/lightek_mail_ingress.py" ]]
[[ -f /etc/lightek/mail-ingress.json ]]
# This installer is scoped to Lightek's existing virtual mailbox setup.
[[ "$(postconf -h virtual_mailbox_maps)" == hash:/etc/postfix/lightek_recipients ]]
[[ "$(postconf -h virtual_mailbox_domains)" == hash:/etc/postfix/lightek_domains ]]
sudo -u lightek test -r /etc/lightek/mail-ingress.json
# A deliberately invalid token must reach Rails and return 401. Never send the real
# credential in this probe or accept a redirect to a different application.
sudo -u lightek python3 - <<'PY'
import json, urllib.error, urllib.request
with open('/etc/lightek/mail-ingress.json') as file:
    config = json.load(file)
if not config['url'].startswith('https://') or len(config['token']) < 32:
    raise SystemExit('Invalid ingress configuration')
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args): return None
request = urllib.request.Request(config['url'], data=b'', method='POST', headers={'X-Lightek-Mail-Ingress': 'routing-check-invalid-token'})
try:
    urllib.request.build_opener(NoRedirect()).open(request, timeout=15)
except urllib.error.HTTPError as error:
    if error.code != 401:
        raise SystemExit(f'Ingress not ready: HTTP {error.code}. Deploy/reload Rails with its ingress token first.')
else:
    raise SystemExit('Ingress did not reject an invalid token')
# With the real token, an empty envelope must fail validation (422), not auth.
# No email is created and no message is sent by either probe.
request = urllib.request.Request(config['url'], data=b'', method='POST', headers={
    'X-Lightek-Mail-Ingress': config['token'], 'X-Lightek-Mail-Recipients': '[]'})
try:
    urllib.request.build_opener(NoRedirect()).open(request, timeout=15)
except urllib.error.HTTPError as error:
    if error.code != 422:
        raise SystemExit(f'Ingress credential check failed: HTTP {error.code}')
else:
    raise SystemExit('Ingress unexpectedly accepted an empty envelope')
PY
backup="/var/backups/lightek-mail/receiving-$(date -u +%Y%m%dT%H%M%S)-$$"
install -d -m 0700 "$backup"
cp -a /etc/postfix/main.cf /etc/postfix/master.cf "$backup/"
# Create the managed map before syncing; subsequent timer runs keep all maps current.
touch "$MAP"
bash "$APP_DIR/lib/scripts/sync_lightek_mail_recipients.sh"
# master.cf argv is tokenized by Postfix, so reject paths containing whitespace.
[[ "$APP_DIR" =~ ^/[a-zA-Z0-9_./-]+$ ]]
postconf -M "lightek_mail/unix=lightek_mail unix - n n - - pipe flags=Rq user=lightek argv=/usr/bin/python3 $APP_DIR/lib/scripts/lightek_mail_ingress.py --recipient \${recipient}"
postconf -e 'lightek_mail_destination_recipient_limit = 1'
existing="$(postconf -h transport_maps)"
if [[ ! "${existing//,/ } " =~ (^|[[:space:]])hash:/etc/postfix/lightek_transports[[:space:]] ]]; then
  postconf -e "transport_maps = hash:$MAP${existing:+, $existing}"
fi
# Keep new/disabled mailboxes synchronized without requiring another deployment.
cat > /etc/systemd/system/lightek-mail-recipient-sync.service <<EOF
[Unit]
Description=Synchronize Lightek Mail recipients and inbox routes
After=network-online.target
[Service]
Type=oneshot
Environment="LIGHTEK_APP_DIR=$APP_DIR"
Environment="LIGHTEK_ENV_FILE=${LIGHTEK_ENV_FILE:-/etc/lightek/lightekmcg-site.env}"
ExecStart=/bin/bash $APP_DIR/lib/scripts/sync_lightek_mail_recipients.sh
EOF
cat > /etc/systemd/system/lightek-mail-recipient-sync.timer <<'EOF'
[Unit]
Description=Refresh Lightek Mail mailbox routes every minute
[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
[Install]
WantedBy=timers.target
EOF
postfix check
systemctl daemon-reload
systemctl enable --now lightek-mail-recipient-sync.timer
if [[ "${2:-}" == --listen-public && "$(postconf -h inet_interfaces)" != all ]]; then
  postconf -e 'inet_interfaces = all'
  postfix check
  systemctl restart postfix
else
  postfix reload
fi
echo "LIGHTEK_MAIL_RECEIVING_ROUTED backup=$backup"
echo 'Verify domain MX, cloud/host inbound TCP 25 and send an external test message. Previously stored Dovecot mail is retained; new deliveries route into Rails.'
