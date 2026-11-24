#!/usr/bin/env bash
set -euo pipefail

domain=$1
revision=$2
profile=$3
shift 3
[[ "$EUID" == 0 && "$domain" =~ ^batch-d-[a-z0-9-]+\.staging\.[a-z0-9.-]+$ && "$revision" =~ ^[0-9a-f]{40}$ ]]
instance="/opt/lightek-sites/$domain"
[[ -f "$instance/managed.json" && -f "$instance/.env" ]]
grep -Fxq 'LIGHTEK_RELEASE_ASSURANCE_TARGET="1"' "$instance/.env"
mapfile -t managed < <(find /opt/lightek-sites -mindepth 2 -maxdepth 2 -name managed.json)
[[ "${#managed[@]}" == 1 && "${managed[0]}" == "$instance/managed.json" ]]
curl --fail --silent --max-time 15 --resolve "$domain:443:127.0.0.1" "https://$domain/__lightek/release" |
  python3 -c 'import json,sys; sys.exit(json.load(sys.stdin).get("source_sha") != sys.argv[1])' "$revision"

read -r operator_ip _ _ ssh_port <<< "${SSH_CONNECTION:?SSH peer required}"
[[ "$ssh_port" =~ ^[0-9]{1,5}$ && $# -gt 0 ]]
DEBIAN_FRONTEND=noninteractive apt-get install -y ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow from "$operator_ip" to any port "$ssh_port" proto tcp
ufw allow 80/tcp
ufw allow 443/tcp

if [[ "$profile" == msp ]]; then
  for network in "$@"; do
    ufw allow from "$network" to any port 3479 proto udp
    ufw allow from "$network" to any port 5350 proto tcp
    ufw allow from "$network" to any port 50110:50159 proto udp
  done
fi
ufw --force enable

if [[ "$profile" == msp ]]; then
  # The native installer prefixes its certificate name. Expose that exact
  # certificate at the location expected by the Batch D installer.
  certificate="/etc/letsencrypt/live/lightek-$domain"
  alias_path="/etc/letsencrypt/live/$domain"
  [[ -r "$certificate/fullchain.pem" && -r "$certificate/privkey.pem" ]]
  if [[ ! -e "$alias_path" && ! -L "$alias_path" ]]; then
    ln -s "$certificate" "$alias_path"
  fi
  [[ "$(realpath "$alias_path")" == "$certificate" ]]
  LIGHTEK_BATCH_D_APPLY=1 bash "$instance/current/deploy/it-support-staging/services.sh" "$domain" "$revision"
fi
