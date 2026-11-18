#!/usr/bin/env python3
"""Add a Dymond Site application to an existing native Passenger runtime."""
import fcntl
import hashlib
import json
import os
import pathlib
import pwd
import re
import signal
import subprocess
import sys
import tempfile
import time
import urllib.request

BOOTSTRAP = r'''
require "json"
c = JSON.parse(STDIN.read)
if c['pwa_member']
  puts 'LIGHTEK_SITE=' + JSON.generate(LightekPwa::SharedAccountRuntime.install!(c))
  exit
end
DymondSite::Site.transaction do
  owner = User.find_or_initialize_by(email_address: c.fetch("owner_email"))
  if owner.new_record?
    owner.assign_attributes(first_name: c.fetch("owner").fetch("first_name"), last_name: c.fetch("owner").fetch("last_name"),
      role: "client", password_setup_required: true, password: SecureRandom.urlsafe_base64(36))
    owner.save!
  end
  host = LightekSettings::SiteDomain.public_hostname!(c.fetch("domain"))
  site = DymondSite::Site.find_or_initialize_by(host: host)
  if site.persisted?
    raise "Hostname is already owned or managed separately" unless site.tenant == owner && site.manifest.to_h["hosted_application_key"] == c.fetch("application_key")
  else
    site.assign_attributes(name: c.fetch("name"), tenant: owner)
    site.save!
    theme = site.themes.create!(name: "Application theme", scope: "site", tokens: {})
    site.update!(active_theme: theme)
    LightekDesign::WebsiteDesigns.apply!(site: site, design: "vinylctrl")
    page = LightekDesign::WebsiteDesigns.import!(site: site, design: "vinylctrl")
    page.update!(slug: "home", title: "Home", published: true, position: 0)
    menu = site.nav_menu || site.create_nav_menu!(name: "Main Menu")
    menu.nav_items.create!(page: page, label: "Home", position: 0)
    site.update!(manifest: site.manifest.to_h.merge("hosted_application_key" => c.fetch("application_key")))
  end
  if c["branding"].is_a?(Hash)
    site.update!(manifest: site.manifest.to_h.merge("agency_branding" => c["branding"].slice("brand_name", "logo_url", "support_email", "accent_color")))
  end
  LightekPwa::Application.find_or_create_by!(site: site) { |pwa| pwa.name = site.name }
  LightekSettings::SiteDomain.verify!(host: host)
  puts "LIGHTEK_SITE=" + JSON.generate({site_id: site.id, application_key: c.fetch("application_key"), domain: site.host})
end
'''


def validate(config):
    host = config["domain"]
    if host.rsplit(".", 1)[-1].isdigit() or host.endswith((".local", ".localhost", ".internal", ".home.arpa")):
        raise ValueError("Use a public DNS hostname, not an IP or local hostname")
    if len(host) > 253 or not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+", host):
        raise ValueError("Invalid hostname")
    if not re.fullmatch(r"[a-f0-9-]{36}", config["application_key"]):
        raise ValueError("Invalid application key")
    for key in ("owner_email", "certificate_email"):
        if not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", config[key]):
            raise ValueError("Invalid email")
    for key in ("app_root", "env_file", "ruby_bin"):
        path = config["deployment"][key]
        if not isinstance(path, str) or not re.fullmatch(r"/[A-Za-z0-9_./ -]+", path) or ".." in path.split("/"):
            raise ValueError("Invalid native runtime path")
    if not re.fullmatch(r"[a-zA-Z0-9_][a-zA-Z0-9_.-]*", config["deployment"]["app_user"]):
        raise ValueError("Invalid application user")
    return config


class HostedSite:
    def __init__(self, config, system_root=pathlib.Path("/")):
        self.config = validate(config)
        self.profile = config["deployment"]
        self.root = pathlib.Path(self.profile["app_root"])
        self.host = config["domain"]
        self.key = config["application_key"]
        self.user = pwd.getpwnam(self.profile["app_user"])
        self.system_root = system_root
        self.state = system_root / "var/lib/lightek/hosted-sites" / self.key
        self.state.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.log = self.state / "setup.log"
        self.marker = "# LIGHTEK HOSTED APPLICATION " + self.key

    def run(self, args, input=None, capture=False):
        with self.log.open("ab") as log:
            result = subprocess.run(args, input=input, stdout=subprocess.PIPE if capture else log, stderr=log, check=True, timeout=600)
            return result.stdout.decode() if capture else None

    def bootstrap(self):
        with tempfile.TemporaryDirectory(prefix="lightek-site-") as directory:
            path = pathlib.Path(directory)
            os.chown(path, self.user.pw_uid, self.user.pw_gid)
            script = path / "bootstrap.rb"
            script.write_text(BOOTSTRAP)
            script.chmod(0o600)
            os.chown(script, self.user.pw_uid, self.user.pw_gid)
            command = ["sudo", "-u", self.user.pw_name, "-H", "env", "-u", "GEM_HOME", "-u", "GEM_PATH",
                "PATH=" + self.profile["ruby_bin"] + ":/usr/local/bin:/usr/bin:/bin", "bash", "-c",
                'set -e; set -a; . "$2"; set +a; cd "$1"; exec bundle exec rails runner "$3"',
                "site-create", str(self.root), self.profile["env_file"], str(script)]
            output = self.run(command, input=json.dumps(self.config).encode(), capture=True)
            result = next(line.removeprefix("LIGHTEK_SITE=") for line in output.splitlines() if line.startswith("LIGHTEK_SITE="))
            return json.loads(result)

    def prepare_shared_runtime(self):
        if not self.config.get('pwa_member'):
            return
        domain = self.config['runtime_domain']
        if not re.fullmatch(r'[a-z0-9-]+(?:\.[a-z0-9-]+)+', domain):
            raise ValueError('Invalid shared runtime')
        base = pathlib.Path('/opt/lightek-sites') / domain
        if self.root != base / 'current' or pathlib.Path(self.profile['env_file']) != base / '.env':
            raise ValueError('Account must use the exact shared runtime')
        managed = json.loads((base / 'managed.json').read_text())
        if managed['domain'] != domain or managed['owner_email'] != self.config['runtime_owner_email']:
            raise ValueError('Shared runtime ownership mismatch')
        values = {key: json.loads(value) for key, value in (line.split('=', 1) for line in (base / '.env').read_text().splitlines() if '=' in line)}
        self.runtime_environment_changed = values.get('LIGHTEK_PWA_SHARED_HOSTING') != 'true' or values.get('LIGHTEK_PWA_MEMBER_BACKEND') != 'true'
        values['LIGHTEK_PWA_MEMBER_BACKEND'] = 'true'
        values['LIGHTEK_PWA_SHARED_HOSTING'] = 'true'
        (base / '.env').write_text(''.join(key + '=' + json.dumps(str(value)) + '\n' for key, value in values.items()))
        (base / '.env').chmod(0o600)
        def quote(value):
            return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"') + '"'
        (base / 'passenger-env.conf').write_text(''.join('SetEnv ' + key + ' ' + quote(value) + '\n' for key, value in values.items()))
        (base / 'passenger-env.conf').chmod(0o600)
        worker = 'lightek-' + hashlib.sha256(domain.encode()).hexdigest()[:12] + '-sidekiq'
        if self.profile.get('worker_service', '').removesuffix('.service') != worker:
            raise ValueError('Worker does not belong to the shared runtime')

    def validate_existing_hosts(self):
        for path in (self.system_root / "etc/apache2/sites-enabled").glob("*"):
            content = path.read_text()
            if self.marker in content:
                continue
            for line in content.splitlines():
                parts = line.split()
                if parts and parts[0].lower() in ("servername", "serveralias") and self.host in [part.lower() for part in parts[1:]]:
                    raise ValueError("Hostname already belongs to another virtual host")

    def pause_standby(self):
        standby = self.config.get('standby_runtime')
        if not standby:
            return None
        domain = standby['domain']
        if not re.fullmatch(r'[a-z0-9-]+(?:\.[a-z0-9-]+)+', domain) or domain == self.config['runtime_domain']:
            raise ValueError('Invalid standby runtime')
        base = pathlib.Path('/opt/lightek-sites') / domain
        profile = standby['deployment']
        if profile['app_root'] != str(base / 'current') or profile['env_file'] != str(base / '.env'):
            raise ValueError('Standby runtime path differs')
        managed = json.loads((base / 'managed.json').read_text())
        if managed['domain'] != domain or managed['owner_email'] != standby['owner_email']:
            raise ValueError('Standby runtime ownership differs')
        worker = 'lightek-' + hashlib.sha256(domain.encode()).hexdigest()[:12] + '-sidekiq'
        if profile['worker_service'].removesuffix('.service') != worker:
            raise ValueError('Standby worker differs')
        state = self.system_root / 'var/lib/lightek/fleet' / hashlib.sha256(str((base / 'current').resolve()).encode()).hexdigest()[:24]
        state.mkdir(parents=True, exist_ok=True, mode=0o700)
        with (state / 'update.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            values = {key: json.loads(value) for key, value in (line.split('=', 1) for line in (base / '.env').read_text().splitlines() if '=' in line)}
            compose = ['docker', 'compose', '--env-file', str(base / '.env'), '-p', values['PROJECT'], '-f', str(base / 'dependencies.yml')]
            running = self.run(compose + ['ps', '--status', 'running', '--services'], capture=True).splitlines()
            if 'db' not in running:
                return {'domain': domain, 'state': 'offline'}
            # Never pause an old runtime containing another customer or media.
            check = 'c=JSON.parse(STDIN.read); puts "LIGHTEK_EMPTY="+JSON.generate(User.where.not(email_address:c.fetch("owner_email")).none? && !Post.exists? && !StudioProject.exists? && !ActiveStorage::Blob.exists?)'
            command = ['sudo', '-u', profile['app_user'], '-H', 'python3', str(base / 'run-app.py'), 'bundle', 'exec', 'rails', 'runner', check]
            output = self.run(command, input=json.dumps(standby).encode(), capture=True)
            empty = next(line.removeprefix('LIGHTEK_EMPTY=') for line in output.splitlines() if line.startswith('LIGHTEK_EMPTY='))
            if empty != 'true':
                return {'domain': domain, 'state': 'preserved'}
            self.run(['systemctl', 'stop', profile['worker_service']])
            self.run(compose + ['stop'])
            for suffix in ['', '-ssl']:
                filename = 'lightek-' + domain + suffix + '.conf'
                if (self.system_root / 'etc/apache2/sites-enabled' / filename).exists():
                    self.run(['a2dissite', filename])
            self.run(['apache2ctl', 'configtest']);self.run(['systemctl', 'reload', 'apache2'])
            return {'domain': domain, 'state': 'paused'}

    def write_vhost(self, tls=False):
        suffix = "-ssl" if tls else ""
        filename = "lightek-app-" + self.key + suffix + ".conf"
        path = self.system_root / "etc/apache2/sites-available" / filename
        if path.exists() and self.marker not in path.read_text():
            raise ValueError("Virtual host is managed separately")
        acme = str(self.system_root / "var/www/lightek-acme" / self.host)
        pathlib.Path(acme).mkdir(parents=True, exist_ok=True)
        if tls:
            certificate = str(self.system_root / "etc/letsencrypt/live" / ("lightek-app-" + self.key))
            body = f'''{self.marker}
<VirtualHost *:443>
  ServerName {self.host}
  SSLEngine on
  SSLCertificateFile {certificate}/fullchain.pem
  SSLCertificateKeyFile {certificate}/privkey.pem
  DocumentRoot "{self.root}/public"
  PassengerRuby "{self.profile['ruby_bin']}/ruby"
  PassengerAppRoot "{self.root}"
  PassengerAppEnv production
  IncludeOptional "{self.root.parent}/passenger-env.conf"
  <Directory "{self.root}/public">
    Require all granted
    Options -MultiViews
  </Directory>
</VirtualHost>
'''
        else:
            body = f'''{self.marker}
<VirtualHost *:80>
  ServerName {self.host}
  DocumentRoot {acme}
  Alias /.well-known/acme-challenge/ {acme}/.well-known/acme-challenge/
  <Directory {acme}>
    Require all granted
  </Directory>
  RedirectMatch 302 ^/(?!\\.well-known/acme-challenge/)(.*)$ https://{self.host}/$1
</VirtualHost>
'''
        previous = path.read_text() if path.exists() else None
        path.write_text(body)
        try:
            self.run(["a2ensite", filename])
            self.run(["apache2ctl", "configtest"])
            self.run(["systemctl", "reload", "apache2"])
        except Exception:
            if previous is not None:
                path.write_text(previous)
            else:
                self.run(["a2dissite", filename])
                path.unlink(missing_ok=True)
            raise

    def verify(self):
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, *args, **kwargs):
                return None
        opener = urllib.request.build_opener(NoRedirect())
        if self.config.get('pwa_member'):
            with opener.open('https://' + self.host + '/api/lightek/pwa/backend-health', timeout=10) as response:
                result = json.loads(response.read(32768))
                if response.status != 200 or result.get('member_key') != self.key:
                    raise ValueError('Shared account identity does not match')
            return result
        url = "https://" + self.host + "/__lightek/site-health"
        with opener.open(urllib.request.Request(url, headers={"Cache-Control": "no-cache"}), timeout=10) as response:
            result = json.loads(response.read(32768))
            if response.status != 200 or result.get("application_key") != self.key or result.get("domain") != self.host:
                raise ValueError("Public application routing does not match")
        with opener.open(urllib.request.Request("https://" + self.host + "/", headers={"Cache-Control": "no-cache"}), timeout=10) as response:
            html = response.read(1024 * 1024).decode("utf-8")
            if response.status != 200 or 'name="lightek-application-key" content="' + self.key + '"' not in html:
                raise ValueError("Public homepage is not the created application")
        return result

    def execute(self):
        checkout_state = self.system_root / "var/lib/lightek/fleet" / hashlib.sha256(str(self.root.resolve()).encode()).hexdigest()[:24]
        checkout_state.mkdir(mode=0o700, parents=True, exist_ok=True)
        with (self.state / "setup.lock").open("w") as lock, (checkout_state / "update.lock").open("w") as checkout_lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            fcntl.flock(checkout_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.validate_existing_hosts()
            self.prepare_shared_runtime()
            result = self.bootstrap()
            self.write_vhost()
            self.run(["certbot", "certonly", "--webroot", "-w", str(self.system_root / "var/www/lightek-acme" / self.host),
                "-d", self.host, "--email", self.config["certificate_email"], "--agree-tos", "--non-interactive",
                "--keep-until-expiring", "--cert-name", "lightek-app-" + self.key])
            self.write_vhost(tls=True)
            if self.config.get('pwa_member') and self.runtime_environment_changed:
                self.run(['systemctl', 'try-restart', self.profile['worker_service']])
                self.run(['passenger-config', 'restart-app', str(self.root), '--ignore-app-not-running'])
            for attempt in range(12):
                try:
                    health = self.verify()
                    if not self.config.get('pwa_member') and health.get("site_id") != result.get("site_id"):
                        raise ValueError("Application site identity mismatch")
                    result.update(status="succeeded", https_verified=True)
                    if self.config.get('pwa_member'):
                        result['standby_runtime'] = self.pause_standby()
                        self.verify()
                    return result
                except Exception:
                    if attempt == 11:
                        raise
                    time.sleep(5)


if __name__ == "__main__":
    os.umask(0o077)
    try:
        if os.geteuid() != 0:
            raise PermissionError("Root server management access required")
        def interrupted(*_):
            raise TimeoutError("Application setup deadline")
        signal.signal(signal.SIGTERM, interrupted)
        print(json.dumps(HostedSite(json.load(sys.stdin)).execute()))
    except BaseException as error:
        print(json.dumps({"status": "failed", "error_class": type(error).__name__}))
        sys.exit(1)
