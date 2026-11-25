#!/usr/bin/env bash
set -euo pipefail

role="${1:?Slot process required}"
slot="${2:?Slot required}"
case "$slot" in
  blue) web=28100; cable=28101 ;;
  green) web=28200; cable=28201 ;;
  *) exit 2 ;;
esac

export PATH=/home/lightek/.rbenv/versions/3.3.6/bin:/home/lightek/.rbenv/bin:/usr/local/bin:/usr/bin:/bin
export RAILS_ENV=production RACK_ENV=production
export REDIS_URL="${REDIS_URL-redis://127.0.0.1:6379/0}"
unset GEM_HOME GEM_PATH SOLID_QUEUE_IN_PUMA
cd "/var/www/lightekmcg-slots/$slot"

case "$role" in
  web)
    export LIGHTEK_SLOT_PORT="$web" RAILS_SERVE_STATIC_FILES=1
    exec bundle exec puma -C config/puma_slot.rb config.ru ;;
  cable)
    export LIGHTEK_SLOT_PORT="$cable"
    exec bundle exec puma -C config/puma_slot.rb cable/config.ru ;;
  worker)
    exec 9>"/run/lock/lightek-production-workers.lock"
    flock -n 9 || { echo "Another production slot owns the worker lock" >&2; exit 1; }
    legacy="$(systemctl show --property=ActiveState --value lightekmcg-site-sidekiq.service)"
    [[ "$legacy" == inactive || "$legacy" == failed ]] || { echo "Legacy production worker is active" >&2; exit 1; }
    exec bundle exec sidekiq -q default -q mailers -t 35 ;;
  verify-worker)
    expected="${3:?Expected release SHA required}"
    [[ "$expected" =~ ^[0-9a-f]{40}$ ]] || exit 2
    unit="lightek-production-worker@$slot.service"
    pid="$(systemctl show --property=MainPID --value "$unit")"
    [[ "$pid" =~ ^[1-9][0-9]*$ && "$(readlink -f "/proc/$pid/cwd")" == "$(pwd -P)" ]]
    [[ "$(git rev-parse HEAD)" == "$expected" ]]
    LIGHTEK_STUDIO_SIDEKIQ_PID="$pid" LIGHTEK_STUDIO_QUEUE_WAIT_SECONDS=90 timeout 100s bundle exec ruby script/studio/verify_queue_consumer.rb
    systemctl is-active --quiet "$unit"
    [[ "$(systemctl show --property=MainPID --value "$unit")" == "$pid" ]] ;;
  *) exit 2 ;;
esac
