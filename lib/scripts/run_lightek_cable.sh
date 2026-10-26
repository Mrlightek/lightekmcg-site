#!/usr/bin/env bash
set -euo pipefail
APP_ROOT="${APP_ROOT:-/var/www/lightekmcg-site}"
APP_USER="${APP_USER:-lightek}"
RUBY_VERSION="${RUBY_VERSION:-3.3.6}"
ENV_FILE="${ENV_FILE:-/etc/lightek/lightekmcg-site.env}"
unset GEM_HOME GEM_PATH
set -a
source "$ENV_FILE"
set +a
export RAILS_ENV=production RACK_ENV=production
export RBENV_ROOT="/home/${APP_USER}/.rbenv"
export PATH="${RBENV_ROOT}/versions/${RUBY_VERSION}/bin:${RBENV_ROOT}/bin:/usr/local/bin:/usr/bin:/bin"
cd "$APP_ROOT"
mkdir -p tmp/pids
if [[ "${1:-}" == "--check" ]]; then
  exec bundle exec puma --version
fi
exec bundle exec puma -C config/puma_cable.rb cable/config.ru
