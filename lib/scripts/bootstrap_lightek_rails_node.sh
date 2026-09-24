#!/usr/bin/env bash
set -euo pipefail

[[ "${EUID}" -eq 0 ]] || { echo "ERROR: run as root"; exit 1; }

APP_USER="${APP_USER:-lightek}"
APP_NAME="${APP_NAME:-lightekmcg-site}"
APP_ROOT="${APP_ROOT:-/var/www/${APP_NAME}}"
RUBY_VERSION="${RUBY_VERSION:-3.3.6}"
APP_HOME="/home/${APP_USER}"
RBENV_ROOT="${APP_HOME}/.rbenv"
ENV_DIR="/etc/lightek"
ENV_FILE="${ENV_DIR}/${APP_NAME}.env"

echo "=== Lightek bare-metal Rails bootstrap ==="
echo "App user: ${APP_USER}"
echo "App root: ${APP_ROOT}"
echo "Ruby:     ${RUBY_VERSION}"
echo

if ! grep -q 'Ubuntu 24.04' /etc/os-release; then
  echo "WARNING: written for Ubuntu 24.04 LTS."
  grep PRETTY_NAME /etc/os-release || true
fi

POLICY_CREATED=0
if [[ ! -e /usr/sbin/policy-rc.d ]]; then
  cat >/usr/sbin/policy-rc.d <<'EOF'
#!/bin/sh
exit 101
EOF
  chmod +x /usr/sbin/policy-rc.d
  POLICY_CREATED=1
fi

cleanup_policy() {
  if [[ "${POLICY_CREATED}" -eq 1 ]]; then
    rm -f /usr/sbin/policy-rc.d
  fi
}
trap cleanup_policy EXIT

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends   apache2 build-essential git curl ca-certificates gnupg dirmngr apt-transport-https   pkg-config autoconf bison libssl-dev libyaml-dev libreadline-dev zlib1g-dev   libffi-dev libgmp-dev libpq-dev libcurl4-openssl-dev libxml2-dev libxslt1-dev tzdata

curl -fsSL https://oss-binaries.phusionpassenger.com/auto-software-signing-gpg-key-2025.txt   | gpg --dearmor   > /etc/apt/trusted.gpg.d/phusion.gpg

echo "deb https://oss-binaries.phusionpassenger.com/apt/passenger noble main"   > /etc/apt/sources.list.d/passenger.list

apt-get update
apt-get install -y --no-install-recommends libapache2-mod-passenger

cleanup_policy
POLICY_CREATED=0
trap - EXIT

systemctl disable apache2 >/dev/null 2>&1 || true
systemctl stop apache2 >/dev/null 2>&1 || true

if ! id "${APP_USER}" >/dev/null 2>&1; then
  useradd --create-home --shell /bin/bash "${APP_USER}"
fi

mkdir -p "${APP_ROOT}" "${ENV_DIR}"
chown -R "${APP_USER}:www-data" "${APP_ROOT}"
chmod 755 /var/www "${APP_ROOT}"

if [[ ! -d "${RBENV_ROOT}/.git" ]]; then
  sudo -u "${APP_USER}" -H git clone https://github.com/rbenv/rbenv.git "${RBENV_ROOT}"
else
  sudo -u "${APP_USER}" -H git -C "${RBENV_ROOT}" pull --ff-only
fi

mkdir -p "${RBENV_ROOT}/plugins"
if [[ ! -d "${RBENV_ROOT}/plugins/ruby-build/.git" ]]; then
  sudo -u "${APP_USER}" -H git clone https://github.com/rbenv/ruby-build.git "${RBENV_ROOT}/plugins/ruby-build"
else
  sudo -u "${APP_USER}" -H git -C "${RBENV_ROOT}/plugins/ruby-build" pull --ff-only
fi

PROFILE="${APP_HOME}/.bashrc"
if ! grep -q 'RBENV_ROOT=.*/.rbenv' "${PROFILE}" 2>/dev/null; then
  cat >>"${PROFILE}" <<'EOF'

# Lightek Ruby environment
export RBENV_ROOT="$HOME/.rbenv"
export PATH="$RBENV_ROOT/bin:$PATH"
eval "$(rbenv init - bash)"
EOF
fi
chown "${APP_USER}:${APP_USER}" "${PROFILE}"

if [[ ! -x "${RBENV_ROOT}/versions/${RUBY_VERSION}/bin/ruby" ]]; then
  sudo -u "${APP_USER}" -H env     RBENV_ROOT="${RBENV_ROOT}"     PATH="${RBENV_ROOT}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"     "${RBENV_ROOT}/bin/rbenv" install "${RUBY_VERSION}"
fi

sudo -u "${APP_USER}" -H env   RBENV_ROOT="${RBENV_ROOT}"   PATH="${RBENV_ROOT}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"   "${RBENV_ROOT}/bin/rbenv" global "${RUBY_VERSION}"

RUBY_BIN="${RBENV_ROOT}/versions/${RUBY_VERSION}/bin"
"${RUBY_BIN}/gem" install bundler --no-document

a2enmod passenger
a2enmod rewrite
a2enmod headers
a2enmod expires
a2enmod ssl

if [[ ! -e "${ENV_FILE}" && ! -e "${ENV_FILE}.example" ]]; then
  cat >"${ENV_FILE}.example" <<EOF
RAILS_ENV=production
RACK_ENV=production
RAILS_SERVE_STATIC_FILES=true

SECRET_KEY_BASE=CHANGE_ME
RAILS_MASTER_KEY=CHANGE_ME_IF_USED

POSTGRES_HOST=127.0.0.1
POSTGRES_PORT=5432
POSTGRES_DB=lightekmcg_site_production
POSTGRES_USER=CHANGE_ME
POSTGRES_PASSWORD=CHANGE_ME

REDIS_URL=redis://127.0.0.1:6379/1

MINIO_ENDPOINT=http://127.0.0.1:9000
MINIO_ROOT_USER=CHANGE_ME
MINIO_ROOT_PASSWORD=CHANGE_ME
MINIO_BUCKETS=CHANGE_ME

STRIPE_SECRET_KEY=sk_test_CHANGE_ME
STRIPE_WEBHOOK_SECRET=whsec_CHANGE_ME
EOF
  chmod 640 "${ENV_FILE}.example"
  chown root:"${APP_USER}" "${ENV_FILE}.example"
fi

cat >"/etc/apache2/sites-available/${APP_NAME}.conf.example" <<EOF
<VirtualHost *:80>
    ServerName lightekmcg.com
    ServerAlias www.lightekmcg.com

    DocumentRoot ${APP_ROOT}/public

    PassengerRuby ${RUBY_BIN}/ruby
    PassengerAppEnv production

    <Directory ${APP_ROOT}/public>
        Options -MultiViews
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/${APP_NAME}-error.log
    CustomLog \${APACHE_LOG_DIR}/${APP_NAME}-access.log combined
</VirtualHost>
EOF

cat >"/etc/systemd/system/${APP_NAME}-sidekiq.service" <<EOF
[Unit]
Description=${APP_NAME} Sidekiq
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=${APP_USER}
Group=${APP_USER}
WorkingDirectory=${APP_ROOT}
Environment=HOME=${APP_HOME}
Environment=RAILS_ENV=production
Environment=RACK_ENV=production
EnvironmentFile=${ENV_FILE}
ExecStart=${RUBY_BIN}/bundle exec sidekiq -e production
Restart=always
RestartSec=5
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl disable "${APP_NAME}-sidekiq.service" >/dev/null 2>&1 || true

echo
echo "=== Validation ==="
sudo -u "${APP_USER}" -H "${RUBY_BIN}/ruby" -v
sudo -u "${APP_USER}" -H "${RUBY_BIN}/bundle" -v
/usr/bin/passenger-config validate-install --auto || true
apache2ctl -M 2>/dev/null | grep passenger || true

echo
echo "=== Bootstrap complete ==="
echo "Apache is intentionally stopped/disabled until cutover."
echo "Sidekiq is intentionally disabled until app + REDIS_URL are ready."
echo "Next:"
echo "  1. Put app code in ${APP_ROOT}"
echo "  2. Create ${ENV_FILE} from ${ENV_FILE}.example"
echo "  3. Publish Docker Redis to 127.0.0.1:6379"
echo "  4. Test bundle/Rails/database manually"
echo "  5. Cut traffic from Traefik to Apache only after validation"
