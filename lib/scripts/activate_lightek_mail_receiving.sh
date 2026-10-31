#!/usr/bin/env bash
# Connect the central Postfix virtual mailbox maps to Rails webmail.
# Supports either a combined application host or a separate mail-only VM.
set -euo pipefail
APP_DIR="${LIGHTEK_APP_DIR:-/var/www/lightekmcg-site}"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNTIME_DIR=/usr/local/lib/lightek-mail
INGRESS_CONFIG=/var/lib/lightek-mail/ingress.json
MAP=/etc/postfix/lightek_transports
REMOTE_ROUTES=0
PUBLIC_LISTENER=0
if [[ "${1:-}" != --apply ]]; then
  echo "Usage: sudo LIGHTEK_APP_DIR=/var/www/lightekmcg-site bash lib/scripts/activate_lightek_mail_receiving.sh --apply [--remote] [--listen-public]"
  echo "Installs exact-recipient HTTPS routing and a mailbox sync timer. --listen-public additionally opens the Postfix listener on all interfaces (requires a restart)."
  exit 0
fi
[[ "$EUID" -eq 0 ]] || { echo 'Run as root on the central mail host.' >&2; exit 1; }
shift
for option in "$@"; do
  case "$option" in
    --remote) REMOTE_ROUTES=1 ;;
    --listen-public) PUBLIC_LISTENER=1 ;;
    *) echo "Unknown option: $option" >&2; exit 1 ;;
  esac
done
[[ "$APP_DIR" =~ ^/[a-zA-Z0-9_./-]+$ ]]
[[ "${LIGHTEK_ENV_FILE:-/etc/lightek/lightekmcg-site.env}" =~ ^/[a-zA-Z0-9_./-]+$ ]]
if [[ "$REMOTE_ROUTES" != 1 ]]; then
  [[ -f "$APP_DIR/config/environment.rb" ]]
fi
for script in lightek_mail_ingress.py fetch_lightek_mail_routes.py lightek_mail_route_maps.py sync_lightek_mail_recipients.sh; do
  [[ -f "$SOURCE_DIR/$script" ]]
done
[[ -f /etc/lightek/mail-ingress.json ]] || { echo "Missing /etc/lightek/mail-ingress.json; prepare the matching ingress credential first." >&2; exit 1; }
# This installer is scoped to Lightek's existing virtual mailbox setup.
[[ "$(postconf -h virtual_mailbox_maps)" == hash:/etc/postfix/lightek_recipients ]] || { echo "Unsupported virtual_mailbox_maps; expected hash:/etc/postfix/lightek_recipients. Existing routing was not changed." >&2; exit 1; }
[[ "$(postconf -h virtual_mailbox_domains)" == hash:/etc/postfix/lightek_domains ]] || { echo "Unsupported virtual_mailbox_domains; expected hash:/etc/postfix/lightek_domains. Existing routing was not changed." >&2; exit 1; }
# A mail-only VM needs no Rails user/database. Its pipe runs without login access.
if ! id lightek >/dev/null 2>&1; then
  [[ "$REMOTE_ROUTES" == 1 ]] || { echo 'Application user lightek is missing' >&2; exit 1; }
  useradd --system --user-group --home-dir /var/lib/lightek-mail --shell /usr/sbin/nologin lightek
fi
# The original /etc/lightek directory can be root-only on a dedicated mail VM.
# Give the pipe a private, traversable credential path without changing access
# to the rest of the application's secrets.
install -d -o root -g "$(id -gn lightek)" -m 0710 /var/lib/lightek-mail
candidate="$(mktemp /var/lib/lightek-mail/.ingress.XXXXXXXX)"
trap 'rm -f "$candidate"' EXIT
install -o lightek -g "$(id -gn lightek)" -m 0600 /etc/lightek/mail-ingress.json "$candidate"
# A deliberately invalid token must reach Rails and return 401. Never send the real
# credential in this probe or accept a redirect to a different application.
runuser -u lightek -- python3 - "$candidate" <<'PY'
import json, sys, urllib.error, urllib.request
with open(sys.argv[1]) as file:
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
mv -f "$candidate" "$INGRESS_CONFIG"
backup="/var/backups/lightek-mail/receiving-$(date -u +%Y%m%dT%H%M%S)-$$"
install -d -m 0700 "$backup"
cp -a /etc/postfix/main.cf /etc/postfix/master.cf "$backup/"
# Create the managed map before syncing; subsequent timer runs keep all maps current.
install -d -o root -g root -m 0755 "$RUNTIME_DIR"
for script in lightek_mail_ingress.py fetch_lightek_mail_routes.py lightek_mail_route_maps.py sync_lightek_mail_recipients.sh; do
  install -o root -g root -m 0644 "$SOURCE_DIR/$script" "$RUNTIME_DIR/$script"
done
touch "$MAP"
LIGHTEK_MAIL_REMOTE_ROUTES="$REMOTE_ROUTES" LIGHTEK_MAIL_INGRESS_CONFIG="$INGRESS_CONFIG" bash "$RUNTIME_DIR/sync_lightek_mail_recipients.sh"
# master.cf argv is tokenized by Postfix, so reject paths containing whitespace.
[[ "$APP_DIR" =~ ^/[a-zA-Z0-9_./-]+$ ]]
postconf -M "lightek_mail/unix=lightek_mail unix - n n - - pipe flags=Rq user=lightek argv=/usr/bin/python3 $RUNTIME_DIR/lightek_mail_ingress.py --config $INGRESS_CONFIG --recipient \${recipient}"
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
Environment="LIGHTEK_MAIL_REMOTE_ROUTES=$REMOTE_ROUTES"
Environment="LIGHTEK_MAIL_INGRESS_CONFIG=$INGRESS_CONFIG"
Environment="LIGHTEK_APP_DIR=$APP_DIR"
Environment="LIGHTEK_ENV_FILE=${LIGHTEK_ENV_FILE:-/etc/lightek/lightekmcg-site.env}"
ExecStart=/bin/bash $RUNTIME_DIR/sync_lightek_mail_recipients.sh
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
if [[ "$PUBLIC_LISTENER" == 1 && "$(postconf -h inet_interfaces)" != all ]]; then
  postconf -e 'inet_interfaces = all'
  postfix check
  systemctl restart postfix
else
  postfix reload
fi
echo "LIGHTEK_MAIL_RECEIVING_ROUTED backup=$backup"
echo 'Verify domain MX, cloud/host inbound TCP 25 and send an external test message. Previously stored Dovecot mail is retained; new deliveries route into Rails.'
