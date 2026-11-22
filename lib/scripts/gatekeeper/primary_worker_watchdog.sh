#!/usr/bin/env bash
set -euo pipefail
umask 077

state=/var/lib/lightek/primary-worker-watchdog
worker=lightekmcg-site-sidekiq.service
app_root=/var/www/lightekmcg-site
domain=lightekmcg.com
[[ -f "$state/verified-release" ]] || exit 0

checkout="$(readlink -f "$app_root")"
lock_key="$(printf '%s' "$checkout" | sha256sum | cut -c1-24)"
exec 9>"/var/lib/lightek/fleet/$lock_key/update.lock"
flock -n 9 || exit 0
read -r release < "$state/verified-release"
[[ "$release" =~ ^[a-f0-9]{40}$ ]] || exit 1
[[ "$(git -c safe.directory="$checkout" -C "$checkout" rev-parse HEAD)" == "$release" ]] || exit 0

if systemctl is-active --quiet "$worker"; then
  rm -f -- "$state/attempted-release"
  exit 0
fi
systemctl is-failed --quiet "$worker" || exit 0
[[ "$(cat "$state/attempted-release" 2>/dev/null || true)" != "$release" ]] || exit 0

verify_web() {
  local payload
  systemctl is-active --quiet apache2.service || return 1
  payload="$(curl --fail --silent --show-error --max-time 10 --resolve "$domain:443:127.0.0.1" \
    -H 'Cache-Control: no-cache' "https://$domain/__lightek/release")" || return 1
  printf '%s' "$payload" | python3 -c 'import json, sys; r=json.load(sys.stdin); sys.exit(r.get("component") != "lightek_app" or r.get("source_sha") != sys.argv[1])' "$release"
}
verify_web || exit 1
printf '%s\n' "$release" > "$state/attempted-release"
systemctl start "$worker"
systemctl is-active --quiet "$worker"
pid="$(systemctl show --property=MainPID --value "$worker")"
[[ "$pid" =~ ^[1-9][0-9]*$ ]]
verify_web
timeout 50s runuser -u lightek -- /bin/bash -c '
  set -ea
  source /etc/lightek/lightekmcg-site.env
  set +a
  export PATH=/home/lightek/.rbenv/shims:/usr/local/bin:/usr/bin:/bin
  export REDIS_URL=redis://127.0.0.1:6379/0
  export LIGHTEK_STUDIO_SIDEKIQ_PID="$1"
  cd "$2"
  exec bundle exec ruby script/studio/verify_queue_consumer.rb
' lightek-primary-worker "$pid" "$checkout"
printf 'GATEKEEPER_PRIMARY_WORKER_RECOVERED release=%s\n' "$release"
