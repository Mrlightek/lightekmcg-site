#!/usr/bin/env bash
# Paid-instance replication: native Rails/Passenger, Docker dependencies only.
set -euo pipefail
[[ "$EUID" = 0 ]] || { echo 'Root is required by the provisioning pipeline.' >&2; exit 1; }
. /etc/os-release
[[ "$ID" = ubuntu && "$VERSION_ID" = 24.04 ]] || { echo "The native Studio instance profile requires Ubuntu 24.04." >&2; exit 1; }
cd "$(dirname "$0")"
STAGE="$PWD"
MIGRATION_STARTED=0
LEGACY=0
readarray -t CONFIG < <(python3 - <<'PY'
import json
c=json.load(open('settings.json'))
for key in ['domain','release','email','bundler','source_sha']:print(c[key])
PY
)
DOMAIN=${CONFIG[0]};RELEASE=${CONFIG[1]};EMAIL=${CONFIG[2]};BUNDLER=${CONFIG[3]};SOURCE_SHA=${CONFIG[4]}
[[ "$DOMAIN" =~ ^[a-z0-9][a-z0-9.-]+\.[a-z]{2,63}$ && "$RELEASE" =~ ^[a-f0-9]{20}$ && "$SOURCE_SHA" =~ ^[a-f0-9]{40}$ ]] || exit 1
KEY=$(printf '%s' "$DOMAIN" | sha256sum | cut -c1-12)
PROJECT="lt_$(printf '%s' "$DOMAIN" | sha256sum | cut -c1-16)"
APP_USER=lightek
APP_NAME="lightek-$KEY"
BASE="/opt/lightek-sites/$DOMAIN"
APP_ROOT="$BASE/current"
RELEASE_DIR="$BASE/releases/$RELEASE"
ENV_FILE="$BASE/.env"
RUBY_BIN="/home/$APP_USER/.rbenv/versions/3.3.6/bin"
exec 9>"/var/lock/lightek-site-$DOMAIN.lock";flock -n 9
exec 8>/var/lock/lightek-build.lock;flock -n 8
if [[ -d "$BASE" && ! -f "$BASE/managed.json" ]]; then echo 'Instance path has no Lightek ownership record.' >&2;exit 1;fi
if [[ -e "$APP_ROOT" ]];then
 FLEET_KEY=$(readlink -f "$APP_ROOT" | tr -d '\n' | sha256sum | cut -c1-24)
 install -d -m 0700 "/var/lib/lightek/fleet/$FLEET_KEY"
 exec 7>"/var/lib/lightek/fleet/$FLEET_KEY/update.lock";flock -n 7
fi
install -d -m 0755 "$BASE" "$BASE/releases"
if [[ -f "$BASE/.env" ]];then
 install -d -m 0700 "$BASE/backups"
 cp "$BASE/.env" "$BASE/backups/environment-before-$RELEASE"
 cp "$BASE/managed.json" "$BASE/backups/managed-before-$RELEASE.json"
 if [[ -f "$BASE/compose.yml" ]] && ! grep -q '"adapter": "native_rails"' "$BASE/managed.json";then LEGACY=1;fi
fi
if [[ ! -x "$RUBY_BIN/ruby" ]] || ! apache2ctl -M 2>/dev/null | grep -q passenger; then
 APP_ROOT="$RELEASE_DIR" APP_USER="$APP_USER" APP_NAME="$APP_NAME" LIGHTEK_KEEP_APACHE=1 MAKE_OPTS=-j1 bash "$STAGE/app/lib/scripts/bootstrap_lightek_rails_node.sh"
fi
usermod -a -G docker "$APP_USER" 2>/dev/null || true
if ! command -v docker >/dev/null; then apt-get update -qq;DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-compose-v2;fi
usermod -a -G docker "$APP_USER"
systemctl enable --now docker
install -d -o "$APP_USER" -g "$APP_USER" -m 0755 "$BASE/shared" "$BASE/shared/storage" "$BASE/shared/tmp" "$BASE/shared/log" "$RELEASE_DIR"
python3 - "$BASE" "$STAGE/settings.json" "$PROJECT" <<'PY'
import base64,json,pathlib,secrets,socket,sys
root=pathlib.Path(sys.argv[1]);c=json.load(open(sys.argv[2]));p=root/'.env'
if p.exists():
 values={key:json.loads(value) for key,value in (line.split('=',1) for line in p.read_text().splitlines() if '=' in line)}
 managed=json.load(open(root/'managed.json'))
 if managed['owner_email']!=c['owner_email'] or managed['domain']!=c['domain']:raise ValueError('Instance belongs to another owner')
else:
 values=dict(POSTGRES_USER='lightek',POSTGRES_DB='lightek_production',POSTGRES_PASSWORD=secrets.token_hex(32),SECRET_KEY_BASE=secrets.token_hex(64),LOCKBOX_MASTER_KEY=secrets.token_hex(32),RAILS_MASTER_KEY=secrets.token_hex(16),LIGHTEK_VAULT_MASTER_KEY=base64.b64encode(secrets.token_bytes(32)).decode(),LIGHTEK_VAULT_KEY_VERSION='1',RAILS_ENV='production',RACK_ENV='production',MAIL_DELIVERY_METHOD='gmail_api')
 values.update(c.get('extra_env',{}))
for name,start in [('POSTGRES_PORT',53000),('LIGHTEK_REDIS_PORT',54000),('APP_PORT',18080)]:
 if name not in values:
  for port in range(start,start+1000):
   sock=socket.socket()
   try:sock.bind(('127.0.0.1',port))
   except OSError:sock.close();continue
   sock.close();values[name]=str(port);break
  else:raise ValueError('No local dependency port available')
values.update(APP_HOST=c['domain'],LIGHTEK_DEPLOYED_SITE_HOST=c['domain'],LIGHTEK_RELEASE=c['release'],PROJECT=sys.argv[3],POSTGRES_HOST='127.0.0.1',DB_HOST='127.0.0.1',REDIS_URL='redis://127.0.0.1:'+values['LIGHTEK_REDIS_PORT']+'/0',RAILS_SERVE_STATIC_FILES='true',BUNDLE_GEMFILE=str(root/'current/Gemfile.native'))
from urllib.parse import quote
values['DATABASE_URL']='postgresql://'+quote(values['POSTGRES_USER'],safe='')+':'+quote(values['POSTGRES_PASSWORD'],safe='')+'@127.0.0.1:'+values['POSTGRES_PORT']+'/'+values['POSTGRES_DB']
import os
with os.fdopen(os.open(p,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600),'w') as file:file.write(''.join(key+'='+json.dumps(str(value))+'\n' for key,value in values.items()))
p.chmod(0o600)
(root/'managed.json').write_text(json.dumps({'domain':c['domain'],'owner_email':c['owner_email'],'project':sys.argv[3],'version':2,'adapter':'native_rails'}))
PY
chown "$APP_USER:$APP_USER" "$ENV_FILE"
cat > "$BASE/dependencies.yml" <<'EOF'
services:
  db:
    image: postgres:16-bookworm
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    ports: ["127.0.0.1:${POSTGRES_PORT}:5432"]
    volumes: ["database:/var/lib/postgresql/data"]
  redis:
    image: redis:7-bookworm
    restart: unless-stopped
    ports: ["127.0.0.1:${LIGHTEK_REDIS_PORT}:6379"]
    command: ["redis-server", "--appendonly", "yes"]
    volumes: ["redis:/data"]
volumes:
  database:
  redis:
EOF
dc(){ docker compose --env-file "$ENV_FILE" -p "$PROJECT" -f "$BASE/dependencies.yml" "$@"; }
dc up -d db redis
for attempt in $(seq 1 60); do dc exec -T db sh -c 'pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"' >/dev/null 2>&1 && break; [[ "$attempt" != 60 ]];sleep 1;done
if [[ -f "$BASE/current-release" ]]; then install -d -m 0700 "$BASE/backups";dc exec -T db sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB"' | gzip > "$BASE/backups/before-$RELEASE.sql.gz";fi
cp -a "$STAGE/app/." "$RELEASE_DIR/"
chmod 0755 "$RELEASE_DIR"
# Preserve vendored gems and generated instance files as untracked overlay files.
chown -R "$APP_USER:$APP_USER" "$RELEASE_DIR"
sudo -u "$APP_USER" -H git -C "$RELEASE_DIR" init
sudo -u "$APP_USER" -H git -C "$RELEASE_DIR" remote add origin https://github.com/Mrlightek/lightekmcg-site.git || true
sudo -u "$APP_USER" -H git -C "$RELEASE_DIR" fetch --depth 1 origin "$SOURCE_SHA"
sudo -u "$APP_USER" -H git -C "$RELEASE_DIR" reset --hard "$SOURCE_SHA"
sudo -u "$APP_USER" -H git -C "$RELEASE_DIR" ls-files -z tmp log storage | sudo -u "$APP_USER" -H git -C "$RELEASE_DIR" update-index -z --skip-worktree --stdin
for name in storage tmp log; do rm -rf "$RELEASE_DIR/$name";ln -s "$BASE/shared/$name" "$RELEASE_DIR/$name";done
chown -R "$APP_USER:$APP_USER" "$RELEASE_DIR" "$BASE/shared"
sudo -u "$APP_USER" python3 "$RELEASE_DIR/lib/scripts/native_instance_overlay.py" apply "$RELEASE_DIR"
# A fixed app path keeps runtime configuration, Passenger and update inventory aligned.
PREVIOUS=$(readlink "$APP_ROOT" || true)
ln -sfn "$RELEASE_DIR" "$BASE/current.new";mv -Tf "$BASE/current.new" "$APP_ROOT"
rollback(){
 code=$?;trap - EXIT;rm -f /run/lightek/bootstrap.json
 if [[ "$code" != 0 && "$MIGRATION_STARTED" = 0 ]];then
  if [[ -f "$BASE/backups/environment-before-$RELEASE" ]];then cp "$BASE/backups/environment-before-$RELEASE" "$ENV_FILE";cp "$BASE/backups/managed-before-$RELEASE.json" "$BASE/managed.json";fi
  if [[ -n "$PREVIOUS" ]];then ln -sfn "$PREVIOUS" "$BASE/current.old";mv -Tf "$BASE/current.old" "$APP_ROOT";passenger-config restart-app "$APP_ROOT" --ignore-app-not-running || true;fi
  if [[ "$LEGACY" = 1 ]];then docker compose --env-file "$ENV_FILE" -p "$PROJECT" -f "$BASE/compose.yml" up -d web worker || true;fi
 fi
 exit "$code"
};trap rollback EXIT
run_app(){ sudo -u "$APP_USER" -H env -u GEM_HOME -u GEM_PATH "PATH=$RUBY_BIN:/usr/local/bin:/usr/bin:/bin" python3 - "$ENV_FILE" "$APP_ROOT" "$@" <<'PY'
import json,os,sys
values={key:json.loads(value) for key,value in (line.split('=',1) for line in open(sys.argv[1]).read().splitlines() if '=' in line)}
os.environ.update({key:str(value) for key,value in values.items()});os.chdir(sys.argv[2]);os.execvp(sys.argv[3],sys.argv[3:])
PY
}
python3 - "$BASE" <<'PYENV'
import pathlib,sys
base=pathlib.Path(sys.argv[1]);script='import json,os,sys\nfrom pathlib import Path\nbase=Path('+repr(str(base))+')\nvalues={k:json.loads(v) for k,v in (line.split("=",1) for line in (base/".env").read_text().splitlines() if "=" in line)}\nos.environ.update(values)\nos.environ["PATH"]="/home/lightek/.rbenv/versions/3.3.6/bin:"+os.environ.get("PATH","")\nos.chdir(base/"current")\nos.execvp(sys.argv[1],sys.argv[1:])\n'
(base/'run-app.py').write_text(script);(base/'run-app.py').chmod(0o644)
PYENV
run_app gem install bundler --version "$BUNDLER" --no-document
run_app bundle config set --local without 'development test'
run_app bundle install --jobs 1
if [[ "$LEGACY" = 1 ]];then docker compose --env-file "$ENV_FILE" -p "$PROJECT" -f "$BASE/compose.yml" stop web worker;fi
MIGRATION_STARTED=1
run_app bundle exec rails db:create db:migrate
install -d -m 0755 /run/lightek
install -o "$APP_USER" -g "$APP_USER" -m 0600 "$STAGE/settings.json" /run/lightek/bootstrap.json
run_app bundle exec rails runner script/lightek_website_bootstrap.rb
rm -f /run/lightek/bootstrap.json
run_app bundle exec rails assets:precompile
run_app bundle exec rails zeitwerk:check
run_app bash lib/scripts/setup_studio_media.sh
# Supply Passenger environment without shell evaluation or exposing it to browsers.
python3 - "$ENV_FILE" "$BASE/passenger-env.conf" <<'PY'
import json,pathlib,sys
values={key:json.loads(value) for key,value in (line.split('=',1) for line in open(sys.argv[1]).read().splitlines() if '=' in line)}
lines=[]
for key,value in values.items():
 value=str(value)
 if any(c in value for c in '\r\n\x00'):raise ValueError('Invalid environment value')
 lines.append('SetEnv '+key+' "'+value.replace('\\','\\\\').replace('"','\\"')+'"')
p=pathlib.Path(sys.argv[2]);p.write_text('\n'.join(lines)+'\n');p.chmod(0o600)
PY
DEBIAN_FRONTEND=noninteractive apt-get install -y certbot python3-certbot-apache
ACME="/var/www/lightek-acme/$DOMAIN";install -d -m 0755 "$ACME"
cat > "/etc/apache2/sites-available/lightek-$DOMAIN.conf" <<EOF
# LIGHTEK WEBSITE $DOMAIN
<VirtualHost *:80>
ServerName $DOMAIN
DocumentRoot $ACME
<Directory $ACME>
Require all granted
</Directory>
</VirtualHost>
EOF
a2ensite "lightek-$DOMAIN.conf";apache2ctl configtest;systemctl enable --now apache2;systemctl reload apache2
if command -v ufw >/dev/null && ufw status | grep -q 'Status: active';then ufw allow 80/tcp;ufw allow 443/tcp;fi
certbot certonly --webroot -w "$ACME" -d "$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive --keep-until-expiring --cert-name "lightek-$DOMAIN" --deploy-hook 'systemctl reload apache2'
systemctl enable --now certbot.timer
a2enmod ssl headers proxy proxy_http proxy_wstunnel
cat > "/etc/apache2/sites-available/lightek-$DOMAIN-ssl.conf" <<EOF
# LIGHTEK WEBSITE $DOMAIN
<VirtualHost *:443>
ServerName $DOMAIN
SSLEngine on
SSLCertificateFile /etc/letsencrypt/live/lightek-$DOMAIN/fullchain.pem
SSLCertificateKeyFile /etc/letsencrypt/live/lightek-$DOMAIN/privkey.pem
DocumentRoot $APP_ROOT/public
PassengerAppRoot $APP_ROOT
PassengerRuby $RUBY_BIN/ruby
PassengerAppEnv production
PassengerUser $APP_USER
Include "$BASE/passenger-env.conf"
<Directory $APP_ROOT/public>
Options -MultiViews
Require all granted
</Directory>
</VirtualHost>
EOF
a2ensite "lightek-$DOMAIN-ssl.conf";apache2ctl configtest;systemctl reload apache2
python3 "$APP_ROOT/lib/scripts/setup_studio_spatial.py" --app-root "$APP_ROOT" --app-user "$APP_USER" --domain "$DOMAIN" --env-file "$ENV_FILE"
cat > "/etc/systemd/system/$APP_NAME-sidekiq.service" <<EOF
[Unit]
After=network.target docker.service
[Service]
User=$APP_USER
SupplementaryGroups=docker
WorkingDirectory=$APP_ROOT
EnvironmentFile=$ENV_FILE
Environment=PATH=$RUBY_BIN:/usr/local/bin:/usr/bin:/bin
ExecStart=$RUBY_BIN/bundle exec sidekiq -c 2
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload;systemctl enable --now "$APP_NAME-sidekiq";systemctl restart "$APP_NAME-sidekiq"
passenger-config restart-app "$APP_ROOT" --ignore-app-not-running
for attempt in $(seq 1 40);do curl --fail --silent --show-error "https://$DOMAIN/__lightek/website-health" > "$BASE/health.json" && break;[[ "$attempt" != 40 ]];sleep 1;done
# The controller performs the full public / owner-login acceptance after this returns.
printf '%s\n' "$RELEASE" > "$BASE/current-release"
printf 'REMOTE_WEBSITE_READY=https://%s\n' "$DOMAIN"
