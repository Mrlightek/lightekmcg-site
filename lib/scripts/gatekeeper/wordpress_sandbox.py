#!/usr/bin/env python3
"""Install/remove one owned disposable WordPress stack. Root helper; JSON stdin only."""
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
import time
import urllib.request

BASE = Path('/opt/lightek-connect-tests')
SITES = Path('/etc/apache2/sites-available')
PLUGIN_FILES = {'lightek-connect.php', 'uninstall.php', 'readme.txt', 'assets/workspace.js', 'assets/workspace.css'}
IMAGES = {'wordpress': 'wordpress:php8.3-apache', 'database': 'mariadb:11.4'}


def validate(c):
    key = c.get('key', '')
    if not re.fullmatch(r'[0-9a-f]{24}', key):
        raise ValueError('Invalid test environment key')
    if c.get('action') not in ('install', 'delete'):
        raise ValueError('Invalid test operation')
    if len(c.get('domain', '')) > 253 or not re.fullmatch(r'wp-test-' + key + r'\.(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}', c.get('domain', '')):
        raise ValueError('Use the generated test subdomain')
    if c['action'] == 'install':
        if not re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', c.get('email', '')):
            raise ValueError('Invalid certificate email')
        secrets = c.get('credentials', {})
        if secrets.get('admin_username') != 'lightek_test' or any(not re.fullmatch(r'[0-9a-f]{48}', secrets.get(k, '')) for k in ('admin_password', 'database_password')):
            raise ValueError('Use generated test credentials')
        files = c.get('plugin_files', {})
        if set(files) != PLUGIN_FILES or any(not isinstance(v, str) or len(v.encode()) > 100_000 for v in files.values()):
            raise ValueError('Invalid bundled connector files')
    return c


def run(args, capture=False, **kwargs):
    result = subprocess.run(args, check=True, stdout=subprocess.PIPE if capture else subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL, timeout=1200, **kwargs)
    return result.stdout.decode().strip() if capture else None


def write(path, content):
    if path.is_symlink():
        raise ValueError('Refusing a symbolic link')
    path.write_text(content)
    path.chmod(0o600)


def compose(c, port):
    password = c['credentials']['database_password']
    return {'services': {
        'database': {'image': IMAGES['database'], 'restart': 'unless-stopped', 'mem_limit': '192m', 'cpus': 0.5,
                     'environment': {'MARIADB_DATABASE': 'wordpress', 'MARIADB_USER': 'wordpress', 'MARIADB_PASSWORD': password, 'MARIADB_ROOT_PASSWORD': password},
                     'command': ['--innodb-buffer-pool-size=64M', '--max-connections=30'], 'volumes': ['database:/var/lib/mysql'],
                     'healthcheck': {'test': ['CMD', 'healthcheck.sh', '--connect', '--innodb_initialized'], 'interval': '5s', 'timeout': '5s', 'retries': 60}},
        'wordpress': {'image': IMAGES['wordpress'], 'restart': 'unless-stopped', 'mem_limit': '192m', 'cpus': 0.5,
                      'ports': [f'127.0.0.1:{port}:80'], 'volumes': ['wordpress:/var/www/html'],
                      'environment': {'WORDPRESS_DB_HOST': 'database', 'WORDPRESS_DB_NAME': 'wordpress', 'WORDPRESS_DB_USER': 'wordpress', 'WORDPRESS_DB_PASSWORD': password,
                                      'WORDPRESS_CONFIG_EXTRA': "define('WP_HOME','https://" + c['domain'] + "'); define('WP_SITEURL','https://" + c['domain'] + "'); define('DISALLOW_FILE_EDIT',true);"},
                      'depends_on': {'database': {'condition': 'service_healthy'}}}},
        'volumes': {'database': {}, 'wordpress': {}}}


def vhost(c, port, challenge, secure=False):
    domain = c['domain']
    header = '# Lightek disposable WordPress ' + c['key'] + '\n'
    plain = f'''<VirtualHost *:80>
ServerName {domain}
Alias /.well-known/acme-challenge/ {challenge}/.well-known/acme-challenge/
<Directory {challenge}>
Require all granted
</Directory>
ProxyPass /.well-known/acme-challenge/ !
ProxyPreserveHost On
ProxyPass / http://127.0.0.1:{port}/
ProxyPassReverse / http://127.0.0.1:{port}/
</VirtualHost>
'''
    if not secure:
        return header + plain
    cert = f'/etc/letsencrypt/live/lightek-wp-test-{c["key"]}'
    tls = f'''<VirtualHost *:443>
ServerName {domain}
SSLEngine on
SSLCertificateFile {cert}/fullchain.pem
SSLCertificateKeyFile {cert}/privkey.pem
ProxyPreserveHost On
RequestHeader set X-Forwarded-Proto "https"
ProxyPass / http://127.0.0.1:{port}/
ProxyPassReverse / http://127.0.0.1:{port}/
</VirtualHost>
'''
    return header + plain + tls


def preflight(root):
    for program in ('docker', 'apache2ctl', 'a2enmod', 'a2ensite', 'a2dissite', 'certbot'):
        if not shutil.which(program):
            raise ValueError('Docker Compose, Apache and Certbot must be installed first')
    run(['docker', 'compose', 'version'])
    memory = dict(re.findall(r'^(\w+):\s+(\d+)', Path('/proc/meminfo').read_text(), re.M))
    if int(memory.get('MemAvailable', 0)) < 384 * 1024 or shutil.disk_usage(root).free < 3 * 1024**3:
        raise ValueError('WordPress test needs 384 MB available RAM and 3 GB free disk')


BOOTSTRAP = r'''
define('WP_INSTALLING',true);
$c=json_decode(stream_get_contents(STDIN),true);
require '/var/www/html/wp-load.php';
require_once ABSPATH.'wp-admin/includes/upgrade.php';
if (!is_blog_installed()) {
  wp_install('Lightek disposable test','lightek_test',$c['email'],false,'',$c['password']);
}
$u=get_user_by('login','lightek_test');
if (!$u || !user_can($u,'manage_options')) { exit(11); }
wp_set_password($c['password'],$u->ID);
require_once ABSPATH.'wp-admin/includes/plugin.php';
$result=activate_plugin('lightek-connect/lightek-connect.php');
if (is_wp_error($result) || !is_plugin_active('lightek-connect/lightek-connect.php')) { exit(12); }
if (!wp_check_password($c['password'],get_user_by('login','lightek_test')->user_pass,$u->ID)) { exit(13); }
'''


def install(c, root, state, compose_args, site):
    if not state:
        for existing in SITES.glob('*'):
            if existing.is_file() and re.search(r'(?:ServerName|ServerAlias)\s+[^\n]*\b' + re.escape(c['domain']) + r'(?:\s|$)', existing.read_text(errors='ignore')):
                raise ValueError('Test hostname already has routing')
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            port = sock.getsockname()[1]
        state = {'key': c['key'], 'domain': c['domain'], 'port': port}
        write(root / 'state.json', json.dumps(state))
    preflight(root)
    write(root / 'compose.json', json.dumps(compose(c, state['port'])))
    run(compose_args + ['pull'])
    run(compose_args + ['up', '-d', '--wait', 'database'])
    run(compose_args + ['up', '-d', 'wordpress'])
    for attempt in range(90):
        try:
            run(compose_args + ['exec', '-T', 'wordpress', 'test', '-f', '/var/www/html/wp-config.php'])
            break
        except subprocess.CalledProcessError:
            if attempt == 89:
                raise ValueError('WordPress startup failed')
            time.sleep(2)
    plugin = root / 'plugin'
    plugin.mkdir(exist_ok=True)
    for name, content in c['plugin_files'].items():
        path = plugin / name
        path.parent.mkdir(exist_ok=True)
        write(path, content)
    run(compose_args + ['cp', str(plugin) + '/.', 'wordpress:/var/www/html/wp-content/plugins/lightek-connect'])
    run(compose_args + ['exec', '-T', 'wordpress', 'chown', '-R', 'www-data:www-data', '/var/www/html/wp-content/plugins/lightek-connect'])
    # WordPress is installed before its public virtual host is enabled.
    run(compose_args + ['exec', '-T', 'wordpress', 'php', '-r', BOOTSTRAP], input=json.dumps({'email': c['email'], 'password': c['credentials']['admin_password']}).encode())
    challenge = root / 'challenge'
    (challenge / '.well-known/acme-challenge').mkdir(parents=True, exist_ok=True)
    # Apache needs traversal rights only for the public ACME directory.
    root.chmod(0o711)
    challenge.chmod(0o755)
    (challenge / '.well-known').chmod(0o755)
    (challenge / '.well-known/acme-challenge').chmod(0o755)
    run(['a2enmod', 'proxy', 'proxy_http', 'ssl', 'headers'])
    if site.exists() and not site.read_text().startswith('# Lightek disposable WordPress ' + c['key'] + '\n'):
        raise ValueError('Refusing to replace unowned routing')
    write(site, vhost(c, state['port'], challenge))
    run(['apache2ctl', 'configtest'])
    run(['a2ensite', site.name])
    run(['systemctl', 'reload', 'apache2'])
    run(['certbot', 'certonly', '--webroot', '-w', str(challenge), '--cert-name', 'lightek-wp-test-' + c['key'], '-d', c['domain'], '--email', c['email'], '--agree-tos', '--non-interactive'])
    write(site, vhost(c, state['port'], challenge, secure=True))
    run(['apache2ctl', 'configtest'])
    run(['systemctl', 'reload', 'apache2'])
    with urllib.request.urlopen('https://' + c['domain'] + '/wp-login.php', timeout=20) as response:
        if response.status != 200 or b'user_login' not in response.read(200_000):
            raise ValueError('Public WordPress login verification failed')
    return {'key': c['key'], 'domain': c['domain'], 'status': 'ready', 'plugin_active': True, 'admin_login_verified': True}


def remove(c, root, state, compose_args, site):
    if not state:
        if site.exists() or root.exists():
            raise ValueError('Test ownership state is missing; cleanup stopped')
        return {'key': c['key'], 'domain': c['domain'], 'status': 'deleted'}
    if site.exists():
        if not site.read_text().startswith('# Lightek disposable WordPress ' + c['key'] + '\n'):
            raise ValueError('Routing ownership changed; cleanup stopped')
        run(['a2dissite', site.name])
        run(['apache2ctl', 'configtest'])
        run(['systemctl', 'reload', 'apache2'])
        site.unlink()
    if (root / 'compose.json').exists():
        run(compose_args + ['down', '--volumes', '--remove-orphans'])
    cert = Path('/etc/letsencrypt/renewal') / ('lightek-wp-test-' + c['key'] + '.conf')
    if cert.exists():
        run(['certbot', 'delete', '--cert-name', 'lightek-wp-test-' + c['key'], '--non-interactive'])
    shutil.rmtree(root)
    return {'key': c['key'], 'domain': c['domain'], 'status': 'deleted'}


def main(c):
    validate(c)
    if os.geteuid() != 0:
        raise ValueError('Root is required')
    os.umask(0o077)
    if BASE.is_symlink():
        raise ValueError('Invalid test environment root')
    BASE.mkdir(mode=0o711, exist_ok=True)
    with Path('/run/lightek-wordpress-sandbox.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        root = BASE / c['key']
        if root.is_symlink():
            raise ValueError('Invalid test environment directory')
        state_path = root / 'state.json'
        state = json.loads(state_path.read_text()) if state_path.exists() else None
        if state and (state.get('key') != c['key'] or state.get('domain') != c['domain']):
            raise ValueError('Test ownership does not match')
        args = ['docker', 'compose', '--project-name', 'lightek-wp-test-' + c['key'], '-f', str(root / 'compose.json')]
        site = SITES / ('lightek-wp-test-' + c['key'] + '.conf')
        if c['action'] == 'delete':
            return remove(c, root, state, args, site)
        root.mkdir(mode=0o700, exist_ok=True)
        return install(c, root, state, args, site)


if __name__ == '__main__':
    try:
        print(json.dumps(main(json.load(sys.stdin))))
    except Exception as error:
        # Never return subprocess output or credential-bearing configuration.
        safe_reasons = {'WordPress test needs 384 MB available RAM and 3 GB free disk', 'Docker Compose, Apache and Certbot must be installed first'}
        receipt = {'status': 'failed', 'error_class': type(error).__name__}
        if str(error) in safe_reasons:
            receipt['reason'] = str(error)
        print(json.dumps(receipt))
        sys.exit(1)
