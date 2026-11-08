#!/usr/bin/env python3
"""Idempotent single-site LiveKit installation; JSON stdin, secret-free receipt."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import urllib.request

def run(*args):
    return subprocess.run(args, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=600)

def configuration(payload):
    domain = payload['domain']
    if not re.fullmatch(r'[a-z0-9](?:[a-z0-9.-]{1,251})[a-z0-9]', domain) or '.' not in domain:
        raise ValueError('Invalid media hostname')
    for key in ('api_key', 'api_secret'):
        if not re.fullmatch(r'[a-zA-Z0-9]{24,128}', payload[key]):
            raise ValueError('Invalid media credential')
    return {'port': 7880, 'bind_addresses': ['127.0.0.1'],
            'rtc': {'tcp_port': 7881, 'port_range_start': 50000, 'port_range_end': 50100, 'use_external_ip': True},
            'turn': {'enabled': True, 'domain': domain, 'udp_port': 3478},
            'keys': {payload['api_key']: payload['api_secret']}, 'logging': {'level': 'warn'}}

def patch_vhost(text, domain):
    # Only a single HTTPS virtual host for this exact website can be changed.
    if len(re.findall(r'<VirtualHost\b', text, re.I)) != 1 or not re.search(r'<VirtualHost\s+[^>]*:443\s*>', text, re.I):
        raise ValueError('A dedicated HTTPS virtual host is required')
    match = re.search(r'^\s*ServerName\s+' + re.escape(domain) + r'\s*$', text, re.M)
    if not match:
        raise ValueError('Virtual host identity mismatch')
    marker = '# LIGHTEK SESSION MEDIA'
    if marker in text:
        return text
    proxy = '\n  '+marker+'\n  ProxyPass "/rtc/" "http://127.0.0.1:7880/" upgrade=websocket\n  ProxyPassReverse "/rtc/" "http://127.0.0.1:7880/"\n'
    return text[:match.end()] + proxy + text[match.end():]

def apply(payload):
    config = configuration(payload)
    if os.geteuid() != 0:
        raise ValueError('Managed installation requires root')
    memory = int(re.search(r'MemTotal:\s+(\d+)', Path('/proc/meminfo').read_text()).group(1))
    if memory < 1800000:
        raise ValueError('Use a server with at least 2 GB RAM')
    domain = payload['domain']
    root = Path('/opt/lightek/session-media')
    state = root / 'owner.json'
    if state.exists() and json.loads(state.read_text())['domain'] != domain:
        raise ValueError('This server already has media assigned to another website')
    candidates = []
    for file in Path('/etc/apache2/sites-enabled').glob('*.conf'):
        text = file.read_text()
        if re.search(r'^\s*ServerName\s+' + re.escape(domain) + r'\s*$', text, re.M) and ':443' in text:
            candidates.append(file.resolve())
    if len(candidates) != 1:
        raise ValueError('Find exactly one active HTTPS virtual host for this website')
    vhost = candidates[0]
    original = vhost.read_text()
    updated = patch_vhost(original, domain)
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    root.chmod(0o700)
    (root / 'livekit.json').write_text(json.dumps(config))
    (root / 'livekit.json').chmod(0o600)
    compose = {'services': {'media': {'image': 'livekit/livekit-server:v1.13.11', 'restart': 'unless-stopped',
        'network_mode': 'host', 'command': ['--config', '/config/livekit.json'],
        'volumes': [str(root / 'livekit.json') + ':/config/livekit.json:ro'],
        'logging': {'driver': 'json-file', 'options': {'max-size': '10m', 'max-file': '3'}}}}}
    (root / 'compose.json').write_text(json.dumps(compose))
    if not shutil.which('docker'):
        run('apt-get', 'update', '-qq')
        run('apt-get', 'install', '-y', 'docker.io', 'docker-compose-v2')
    run('systemctl', 'enable', '--now', 'docker')
    run('a2enmod', 'proxy', 'proxy_http', 'proxy_wstunnel')
    # Persist ownership before starting so retries cannot repurpose another website.
    state.write_text(json.dumps({'domain': domain}))
    state.chmod(0o600)
    run('docker', 'compose', '-p', 'lightek-session-media', '-f', str(root / 'compose.json'), 'up', '-d')
    vhost.write_text(updated)
    try:
        run('apache2ctl', 'configtest')
        run('systemctl', 'reload', 'apache2')
    except Exception:
        vhost.write_text(original)
        run('apache2ctl', 'configtest')
        raise
    if shutil.which('ufw'):
        for port in ('7881/tcp', '3478/udp', '50000:50100/udp'):
            run('ufw', 'allow', port)
    for attempt in range(30):
        try:
            with urllib.request.urlopen('http://127.0.0.1:7880/', timeout=2) as response:
                if response.status == 200:
                    with urllib.request.urlopen('https://' + domain + '/rtc/', timeout=10) as public_response:
                        if public_response.status != 200:
                            raise RuntimeError('HTTPS media proxy health check failed')
                    return {'status': 'ready', 'domain': domain, 'version': '1.13.11'}
        except Exception:
            time.sleep(1)
    raise RuntimeError('Media health check failed')

if __name__ == '__main__':
    try:
        print(json.dumps(apply(json.load(sys.stdin))))
    except Exception as error:
        print(json.dumps({'status': 'failed', 'error_class': type(error).__name__, 'reason': str(error) if isinstance(error, ValueError) else 'Managed media installation failed'}))
        sys.exit(1)
