#!/usr/bin/env python3
"""Install a local Action Cable backend and proxy only the existing TLS /cable endpoint."""
import argparse
import base64
import datetime
import grp
import hashlib
import http.client
import os
import pathlib
import pwd
import re
import shutil
import socket
import ssl
import subprocess
import sys
import tempfile
import time

MARKER = "# LIGHTEK MANAGED ACTION CABLE v1"
BEGIN = "# BEGIN LIGHTEK CABLE PROXY"
END = "# END LIGHTEK CABLE PROXY"
PORT = 28080

def proxy_block():
    return f'''{BEGIN}
    <Location "/cable">
      <IfModule passenger_module>
        PassengerEnabled off
      </IfModule>
      ProxyPreserveHost On
      RequestHeader set X-Forwarded-Proto "expr=%{{REQUEST_SCHEME}}"
      ProxyPass "http://127.0.0.1:{PORT}/cable" upgrade=websocket timeout=7200
      ProxyPassReverse "http://127.0.0.1:{PORT}/cable"
    </Location>
    {END}'''

def patch_vhosts(text, domain):
    """Keep every nonmatching virtual host byte-for-byte intact."""
    count = 0
    def update(match):
        nonlocal count
        block = match.group(0)
        names = []
        for line in block.splitlines():
            line = line.split('#', 1)[0]
            found = re.match(r'^\s*Server(?:Name|Alias)\s+(.+)', line, re.I)
            if found:
                names.extend(name.lower().split(':')[0] for name in found.group(1).split())
        secure = ':443' in match.group(1) or re.search(r'^\s*SSLEngine\s+on\s*$', block, re.I | re.M)
        if domain not in names or not secure:
            return block
        if BEGIN in block:
            existing = re.search(re.escape(BEGIN) + r'.*?' + re.escape(END), block, re.S)
            if not existing or existing.group(0) != proxy_block():
                raise RuntimeError('An existing managed cable block was customized; refusing to overwrite it.')
            count += 1
            return block
        active_lines = '\n'.join(line.split('#', 1)[0] for line in block.splitlines())
        if '/cable' in active_lines:
            raise RuntimeError('The TLS virtual host already has /cable directives; refusing to add a competing mapping.')
        count += 1
        return re.sub(r'</VirtualHost\s*>', '    ' + proxy_block() + '\n</VirtualHost>', block, count=1, flags=re.I)
    updated = re.sub(r'<VirtualHost\s+([^>]+)>.*?</VirtualHost\s*>', update, text, flags=re.I | re.S)
    return updated, count

def run(args, check=True):
    result = subprocess.run(args, capture_output=True, text=True)
    if check and result.returncode:
        raise RuntimeError(f'{args[0]} failed: ' + (result.stderr or result.stdout).strip()[-1200:])
    return result

def atomic_write(path, data, mode=0o644):
    path.parent.mkdir(parents=True, exist_ok=True)
    previous = path.stat() if path.exists() else None
    fd, temporary = tempfile.mkstemp(prefix='.lightek-cable-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as output:
            output.write(data)
        os.chmod(temporary, previous.st_mode & 0o777 if previous else mode)
        if previous:
            os.chown(temporary, previous.st_uid, previous.st_gid)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)

def handshake(host, port, domain, tls=False):
    """An anonymous probe verifies the wire handshake, not application authorization."""
    key = base64.b64encode(os.urandom(16)).decode()
    cls = http.client.HTTPSConnection if tls else http.client.HTTPConnection
    kwargs = {'timeout': 5}
    if tls:
        # Certificate and hostname are checked against the production domain.
        context = ssl.create_default_context()
        sock = context.wrap_socket(socket.create_connection((host, port), timeout=5), server_hostname=domain)
        conn = http.client.HTTPConnection(domain, port, timeout=5)
        conn.sock = sock
    else:
        conn = cls(host, port, **kwargs)
    try:
        conn.request('GET', '/cable', headers={'Host': domain, 'Origin': f'https://{domain}', 'X-Forwarded-Proto': 'https', 'Connection': 'Upgrade', 'Upgrade': 'websocket', 'Sec-WebSocket-Key': key, 'Sec-WebSocket-Version': '13', 'Sec-WebSocket-Protocol': 'actioncable-v1-json'})
        response = conn.getresponse()
        headers = {name.lower(): value for name, value in response.getheaders()}
        expected = base64.b64encode(hashlib.sha1((key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest()).decode()
        valid = response.status == 101 and headers.get('upgrade', '').lower() == 'websocket' and 'upgrade' in [part.strip().lower() for part in headers.get('connection', '').split(',')] and headers.get('sec-websocket-accept') == expected and headers.get('sec-websocket-protocol') == 'actioncable-v1-json' and 'transfer-encoding' not in headers
        if not valid:
            safe = {name: headers.get(name, 'missing') for name in ('connection', 'upgrade', 'sec-websocket-protocol', 'transfer-encoding')}
            raise RuntimeError(f'Invalid WebSocket handshake: HTTP {response.status}, {safe}')
        return True
    finally:
        conn.close()

def wait_for_backend(domain):
    print('Waiting for the authenticated Cable backend to boot...', flush=True)
    for attempt in range(30):
        try:
            handshake('127.0.0.1', PORT, domain)
            return
        except (OSError, http.client.HTTPException, RuntimeError):
            if attempt == 29:
                raise RuntimeError('Cable backend did not pass its handshake check. Inspect journalctl -u lightekmcg-site-cable -n 80.')
            if attempt % 5 == 4:
                print(f'Waiting for backend (attempt {attempt + 1}/30)...', flush=True)
            time.sleep(2)

def restore(snapshots, unit, previously_active, previously_enabled):
    # Remove enablement links while the installed unit file still exists.
    if not previously_active:
        run(['systemctl', 'stop', unit.name], check=False)
    if not previously_enabled:
        run(['systemctl', 'disable', unit.name], check=False)
    for path, data in snapshots.items():
        if data is None:
            path.unlink(missing_ok=True)
        else:
            atomic_write(path, data)
    run(['systemctl', 'daemon-reload'], check=False)
    if previously_active:
        run(['systemctl', 'restart', unit.name], check=False)
    if run(['apache2ctl', 'configtest'], check=False).returncode == 0:
        run(['systemctl', 'reload', 'apache2'], check=False)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Validate prerequisites and preview target files without changing services/configuration')
    parser.add_argument('--probe-backend', action='store_true', help='Wait for the local Cable backend handshake after a deployment restart')
    args = parser.parse_args()
    if args.probe_backend:
        wait_for_backend(os.environ.get('APP_DOMAIN', 'lightekmcg.com'))
        print('LIGHTEK_CABLE_BACKEND_READY')
        return
    if os.geteuid() != 0:
        raise RuntimeError('Run as root on the Ubuntu production server.')
    root = pathlib.Path(os.environ.get('APP_ROOT', '/var/www/lightekmcg-site')).resolve()
    user = os.environ.get('APP_USER', 'lightek')
    domain = os.environ.get('APP_DOMAIN', 'lightekmcg.com').lower()
    env_file = pathlib.Path(os.environ.get('ENV_FILE', '/etc/lightek/lightekmcg-site.env'))
    ruby_version = os.environ.get('RUBY_VERSION', '3.3.6')
    for value in (str(root), str(env_file), user, domain, ruby_version):
        if not re.fullmatch(r'[A-Za-z0-9_./-]+', value):
            raise RuntimeError('Unsupported character in a deployment setting.')
    account = pwd.getpwnam(user)
    group = grp.getgrgid(account.pw_gid).gr_name
    for file in (env_file, root/'cable/config.ru', root/'config/puma_cable.rb', root/'lib/scripts/run_lightek_cable.sh'):
        if not file.is_file():
            raise RuntimeError(f'Missing required file: {file}')
    run(['sudo', '-u', user, '-H', 'env', f'APP_ROOT={root}', f'APP_USER={user}', f'ENV_FILE={env_file}', f'RUBY_VERSION={ruby_version}', 'bash', str(root/'lib/scripts/run_lightek_cable.sh'), '--check'])
    changes = {}
    matches = 0
    visited = set()
    for link in sorted(pathlib.Path('/etc/apache2/sites-enabled').glob('*.conf')):
        path = link.resolve()
        if path in visited:
            continue
        visited.add(path)
        original = path.read_text()
        updated, count = patch_vhosts(original, domain)
        matches += count
        if updated != original:
            changes[path] = updated.encode()
    if not matches:
        raise RuntimeError(f'No enabled TLS virtual host has ServerName or ServerAlias {domain}. No configuration was changed.')
    unit = pathlib.Path('/etc/systemd/system/lightekmcg-site-cable.service')
    if unit.exists() and MARKER not in unit.read_text():
        raise RuntimeError('An unmanaged cable service already exists; refusing to replace it.')
    unit_text = f'''{MARKER}
[Unit]
Description=Lightek authenticated Action Cable backend
After=network.target

[Service]
Type=simple
User={user}
Group={group}
WorkingDirectory={root}
Environment=APP_ROOT={root}
Environment=APP_USER={user}
Environment=ENV_FILE={env_file}
Environment=RUBY_VERSION={ruby_version}
ExecStart=/bin/bash {root}/lib/scripts/run_lightek_cable.sh
Restart=on-failure
RestartSec=3
TimeoutStopSec=30
KillMode=mixed
UMask=0077

[Install]
WantedBy=multi-user.target
'''
    if not unit.exists() or unit.read_text() != unit_text:
        changes[unit] = unit_text.encode()
    print(f'TLS virtual hosts: {matches}; local backend: 127.0.0.1:{PORT}')
    for path in changes:
        print(f'Update: {path}')
    if args.check:
        print('LIGHTEK_CABLE_PREFLIGHT_PASS (no configuration changed)')
        return
    previously_active = run(['systemctl', 'is-active', '--quiet', unit.name], check=False).returncode == 0
    previously_enabled = run(['systemctl', 'is-enabled', '--quiet', unit.name], check=False).returncode == 0
    if not previously_active:
        with socket.socket() as probe:
            if probe.connect_ex(('127.0.0.1', PORT)) == 0:
                raise RuntimeError(f'Port {PORT} is occupied by another service. No configuration changed.')
    backup = pathlib.Path('/var/backups/lightekmcg-site-cable') / datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
    backup.mkdir(parents=True, mode=0o700)
    snapshots = {}
    for index, path in enumerate(changes):
        snapshots[path] = path.read_bytes() if path.exists() else None
        if path.exists():
            shutil.copy2(path, backup/f'{index}-{path.name}')
    (backup/'files.txt').write_text('\n'.join(str(path) for path in changes))
    try:
        run(['a2enmod', 'proxy', 'proxy_http', 'headers'])
        for path, data in changes.items():
            atomic_write(path, data)
        run(['apache2ctl', 'configtest'])
        run(['systemctl', 'daemon-reload'])
        run(['systemctl', 'enable', unit.name])
        run(['systemctl', 'restart', unit.name])
        wait_for_backend(domain)
        run(['systemctl', 'reload', 'apache2'])
        handshake('127.0.0.1', 443, domain, tls=True)
        print(f'LIGHTEK_CABLE_HANDSHAKE_PASS; backup: {backup}')
        print('Reload Live Studio and run a signed-in private test. No firewall port was opened.')
    except Exception:
        restore(snapshots, unit, previously_active, previously_enabled)
        print(f'Installer restored its previous service and virtual-host files. Backup: {backup}', file=sys.stderr)
        raise

if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, KeyError) as error:
        print(f'LIGHTEK_CABLE_SETUP_STOPPED: {error}', file=sys.stderr)
        sys.exit(1)
