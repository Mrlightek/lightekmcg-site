#!/usr/bin/env bash
# Synchronize Postfix's inbound recipients from verified/enabled Lightek Mail
# accounts. Run on the central Ubuntu mail host as root.
set -euo pipefail

APP_DIR="${LIGHTEK_APP_DIR:-/var/www/lightekmcg-site}"
ENV_FILE="${LIGHTEK_ENV_FILE:-/etc/lightek/lightekmcg-site.env}"
MAP="/etc/postfix/lightek_recipients"
RUBY_BIN="/home/lightek/.rbenv/versions/3.3.6/bin"
LOCK="/run/lock/lightek-mail-recipient-sync.lock"

if [[ "$(id -u)" != 0 ]]; then
  echo "Run as root on the central mail host" >&2
  exit 1
fi
for file in "$ENV_FILE" "$APP_DIR/config/environment.rb"; do
  [[ -f "$file" ]] || { echo "Missing: $file" >&2; exit 1; }
done
command -v postmap >/dev/null
command -v postconf >/dev/null
[[ "$(postconf -h virtual_mailbox_maps)" == "hash:$MAP" ]] || {
  echo "Unexpected Postfix virtual_mailbox_maps; refusing to modify." >&2
  exit 1
}
exec 9>"$LOCK"
flock -n 9 || { echo "Recipient sync already running" >&2; exit 1; }
work="$(mktemp -d /etc/postfix/.lightek-recipient-sync.XXXXXXXX)"
trap 'rm -rf "$work"' EXIT

# Query the authoritative Rails database as the app user. Never print credentials.
sudo -u lightek -H bash -c '
  set -e
  export PATH="'"$RUBY_BIN"':$PATH"
  set -a
  source "'"$ENV_FILE"'"
  set +a
  cd "'"$APP_DIR"'"
  RAILS_ENV=production bundle exec rails runner -
' > "$work/runner.out" <<'RUBY'
LightekMail::Account.joins(:domain)
  .where(enabled: true)
  .where.not(lightek_mail_domains: { verified_at: nil })
  .order(:address).pluck(:address).each do |address|
    puts "LIGHTEK_RECIPIENT #{address}"
  end
RUBY

# A marked line is the only accepted output; ignore dotenv diagnostic output.
awk '
  /^LIGHTEK_RECIPIENT / {
    address = substr($0, 19)
    if (address !~ /^[a-z0-9][a-z0-9._+\-]*@[a-z0-9.-]+$/) {
      print "Invalid mailbox address from Rails" > "/dev/stderr"
      exit 2
    }
    print address " lightek"
  }
' "$work/runner.out" | LC_ALL=C sort -u > "$work/lightek_recipients"

count="$(wc -l < "$work/lightek_recipients")"
# Refuse a surprise all-mailbox deletion. An intentional empty list requires
# an operator-approved migration, not an unattended timer run.
if [[ "$count" -lt 1 ]]; then
  echo "No eligible mailboxes returned; keeping current map unchanged." >&2
  exit 1
fi
postmap "hash:$work/lightek_recipients"

# Keep existing authorized domains, including independently provisioned mailboxes.
# Rebuild exact recipient transports only once the receiving installer opts in.
python3 "$APP_DIR/lib/scripts/lightek_mail_route_maps.py" --recipients "$work/lightek_recipients" --domains /etc/postfix/lightek_domains --output "$work"
postmap "hash:$work/lightek_domains"
if [[ -f /etc/postfix/lightek_transports ]]; then
  postmap "hash:$work/lightek_transports"
else
  rm "$work/lightek_transports"
fi

if cmp -s "$work/lightek_recipients" "$MAP" && cmp -s "$work/lightek_domains" /etc/postfix/lightek_domains && { [[ ! -f "$work/lightek_transports" ]] || cmp -s "$work/lightek_transports" /etc/postfix/lightek_transports; }; then
  echo "LIGHTEK_MAIL_RECIPIENTS_UNCHANGED count=$count"
  exit 0
fi

backup="/var/backups/lightek-mail/recipients-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$backup"
chmod 700 "$backup"
[[ ! -f "$MAP" ]] || cp -a "$MAP" "$backup/"
[[ ! -f "$MAP.db" ]] || cp -a "$MAP.db" "$backup/"

# Update hash DB first, then source map. No services are restarted.
install -o root -g root -m 0644 "$work/lightek_recipients.db" "$MAP.db"
install -o root -g root -m 0644 "$work/lightek_recipients" "$MAP"
for name in lightek_domains lightek_transports; do
  [[ -f "$work/$name" ]] || continue
  [[ ! -f "/etc/postfix/$name" ]] || cp -a "/etc/postfix/$name" "$backup/"
  [[ ! -f "/etc/postfix/$name.db" ]] || cp -a "/etc/postfix/$name.db" "$backup/"
  install -o root -g root -m 0644 "$work/$name.db" "/etc/postfix/$name.db"
  install -o root -g root -m 0644 "$work/$name" "/etc/postfix/$name"
done
postfix check
echo "LIGHTEK_MAIL_RECIPIENTS_SYNCED count=$count backup=$backup"
echo "Recipient, domain and enabled inbox route maps synchronized; no DNS, sender or relay settings changed."
