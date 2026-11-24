#!/usr/bin/env bash
set -euo pipefail
umask 077

domain=${1:-}
revision=${2:-}
if [[ ! "$domain" =~ ^batch-d-[a-z0-9]+(-[a-z0-9]+)*\.([a-z0-9-]+\.)+[a-z]{2,}$ || ! "$revision" =~ ^[a-f0-9]{40}$ ]]; then
  echo "Usage: services.sh batch-d-NAME.staging.example.org VERIFIED_COMMIT" >&2
  exit 2
fi
instance="/opt/lightek-sites/$domain"
worker="lightek-$(printf %s "$domain" | sha256sum | cut -c1-12)-sidekiq"
cert="/etc/letsencrypt/live/$domain"

[[ "$EUID" == 0 && -d "$instance/current" && -f "$instance/managed.json" &&
   -r "$cert/fullchain.pem" && -r "$cert/privkey.pem" ]] || {
  echo "Run as root on the dedicated Gatekeeper native website node after its HTTPS deployment." >&2
  exit 1
}

# Require exactly one managed instance and a matching active HTTPS vhost.
mapfile -t instances < <(find /opt/lightek-sites -mindepth 1 -maxdepth 1 -type d -print)
[[ "${#instances[@]}" == 1 && "${instances[0]}" == "$instance" ]] || {
  echo "Expected exactly one managed website on the staging node." >&2
  exit 1
}
mapfile -t tls_vhosts < <(grep -lEi '<VirtualHost[^>]*:443[^>]*>' /etc/apache2/sites-enabled/*.conf)
[[ "${#tls_vhosts[@]}" == 1 ]] &&
  awk -v name="$domain" 'tolower($1)=="servername" && $2==name {found=1} END {exit !found}' "${tls_vhosts[0]}" || {
  echo "Expected only the staging HTTPS virtual host." >&2
  exit 1
}
curl --fail --silent --show-error --max-time 10 --resolve "$domain:443:127.0.0.1" \
  "https://$domain/__lightek/release" | python3 -c \
  'import json,sys; sys.exit(json.load(sys.stdin).get("source_sha") != sys.argv[1])' "$revision"

sudo -u lightek -H python3 "$instance/run-app.py" bin/rails runner \
  deploy/it-support-staging/configure_credentials.rb -- --check "$domain"
if [[ "${LIGHTEK_BATCH_D_APPLY:-0}" != 1 ]]; then
  printf '%s\n' "Verified $domain at $revision. Apply installs coturn, ClamAV and ffprobe on this dedicated node."
  exit 0
fi

mapfile -t public_addresses < <(getent ahostsv4 "$domain" | awk '{print $1}' | sort -u)
[[ "${#public_addresses[@]}" == 1 ]] || { echo "Expected one public IPv4 address for this hostname." >&2; exit 1; }
relay_ip=$(ip -j -4 route get 1.1.1.1 | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["prefsrc"])')
python3 -c 'import ipaddress,sys; sys.exit(not ipaddress.IPv4Address(sys.argv[1]).is_global)' "${public_addresses[0]}"

apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y coturn clamav-daemon ffmpeg
root=/etc/lightek/batch-d
install -d -m 0750 -o root -g turnserver "$root"
if [[ ! -f "$root/turn.secret" ]]; then
  openssl rand -hex 32 > "$root/turn.secret"
fi
install -m 0640 -o root -g turnserver "$cert/fullchain.pem" "$root/turn.crt"
install -m 0640 -o root -g turnserver "$cert/privkey.pem" "$root/turn.key"
{
  cat <<EOF
realm=$domain
listening-ip=$relay_ip
relay-ip=$relay_ip
listening-port=3479
tls-listening-port=5350
min-port=50110
max-port=50159
fingerprint
use-auth-secret
no-cli
no-multicast-peers
no-tcp-relay
denied-peer-ip=0.0.0.0-0.255.255.255
denied-peer-ip=10.0.0.0-10.255.255.255
denied-peer-ip=127.0.0.0-127.255.255.255
denied-peer-ip=169.254.0.0-169.254.255.255
denied-peer-ip=172.16.0.0-172.31.255.255
denied-peer-ip=192.168.0.0-192.168.255.255
user-quota=4
total-quota=24
cert=$root/turn.crt
pkey=$root/turn.key
log-file=stdout
EOF
  if [[ "${public_addresses[0]}" != "$relay_ip" ]]; then
    printf 'external-ip=%s/%s\n' "${public_addresses[0]}" "$relay_ip"
  fi
  printf 'static-auth-secret='
  cat "$root/turn.secret"
} > "$root/turnserver.conf"
chown root:turnserver "$root/turnserver.conf"
chmod 0640 "$root/turnserver.conf"
install -m 0644 "$(dirname "$0")/lightek-batch-d-turn.service" /etc/systemd/system/lightek-batch-d-turn.service

# Match the Rails worker's existing INSTREAM client. ClamAV remains local.
sed -i -E '/^[[:space:]]*(TCPSocket|TCPAddr)[[:space:]]/d' /etc/clamav/clamd.conf
printf '\nTCPSocket 3310\nTCPAddr 127.0.0.1\n' >> /etc/clamav/clamd.conf
"$(dirname "$0")/configure_rails.sh" "$instance" "$domain" "$root/turn.secret"
systemctl daemon-reload
systemctl disable --now coturn.service
systemctl enable --now lightek-batch-d-turn.service
systemctl restart lightek-batch-d-turn.service
sudo -u lightek -H python3 "$instance/run-app.py" ruby deploy/it-support-staging/clamav_probe.rb --signature \
  > /var/lib/clamav/lightek-batch-d-acceptance.ndb
chmod 0644 /var/lib/clamav/lightek-batch-d-acceptance.ndb
systemctl enable --now clamav-freshclam.service clamav-daemon.service
systemctl restart clamav-daemon.service
systemctl restart "$worker.service"
touch "$instance/current/tmp/restart.txt"
printf '%s\n' "Configured $domain. Allow UDP 3479 and 50110-50159 and TCP 5350 at the staging firewall."
