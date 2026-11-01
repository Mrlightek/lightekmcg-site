#!/usr/bin/env python3
"""Configure one registered native installation using Gatekeeper's SSH transport."""
import hashlib
import json
import os
import pathlib
import pwd
import re
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit

KEYS = ('NEVAEH_CENTRAL_URL', 'NEVAEH_INSTALLATION_ID', 'NEVAEH_CENTRAL_TOKEN')


def write_environment(path, values):
    path = pathlib.Path(path)
    if path.is_symlink() or not path.is_file():
        raise ValueError('Existing application environment file required')
    original = path.read_text()
    lines = [line for line in original.splitlines() if not any(line.startswith(key + '=') or line.startswith('export ' + key + '=') for key in KEYS)]
    content = '\n'.join(lines).rstrip() + '\n' + ''.join(key + '=' + json.dumps(values[key]) + '\n' for key in KEYS)
    if content == original:
        return False
    info = path.stat()
    fd, temporary = tempfile.mkstemp(prefix='.nevaeh-env-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as output:
            output.write(content)
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, info.st_mode & 0o777)
        os.chown(temporary, info.st_uid, info.st_gid)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return True


def configure(payload):
    identity = payload['installation_id']
    token = payload['token']
    url = payload['endpoint']
    endpoint = urlsplit(url)
    if type(identity) is not int or identity <= 0 or not re.fullmatch(r'[0-9a-f]{64}', token):
        raise ValueError('Invalid reporting identity')
    if endpoint.scheme != 'https' or not endpoint.hostname or endpoint.username or endpoint.password or endpoint.query or endpoint.fragment or endpoint.path != '/gatekeeper/callbacks/nevaeh_escalation':
        raise ValueError('Invalid central endpoint')
    if any(character in url for character in '$`\\\n\r'):
        raise ValueError('Invalid central endpoint')
    profile = payload['deployment']
    env_file = pathlib.Path(profile['env_file'])
    root = pathlib.Path(profile['app_root'])
    if not env_file.is_absolute() or '..' in env_file.parts or not str(env_file).startswith('/etc/lightek/') or not root.is_absolute() or '..' in root.parts or root.is_symlink():
        raise ValueError('Use the registered native deployment paths')
    user = profile['app_user']
    service = profile['worker_service']
    if not re.fullmatch(r'[a-zA-Z0-9_][a-zA-Z0-9_.@-]*', user) or not re.fullmatch(r'[a-zA-Z0-9_][a-zA-Z0-9_.@-]*', service):
        raise ValueError('Invalid native service profile')
    values = dict(zip(KEYS, (url, str(identity), token)))
    changed = write_environment(env_file, values)
    if changed:
        account = pwd.getpwnam(user)
        marker = root / 'tmp' / 'restart.txt'
        marker.parent.mkdir(exist_ok=True)
        marker.touch()
        os.chown(marker, account.pw_uid, account.pw_gid)
    # Repeat service reload after an interrupted setup even when the env write
    # already committed. This is idempotent and never repeats application work.
    mode = profile.get('worker_mode', 'systemd')
    if mode == 'systemd':
        subprocess.run(['systemctl', 'restart', service], check=True, timeout=90, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(['systemctl', 'is-active', '--quiet', service], check=True, timeout=20)
    elif mode == 'compose':
        command = ['docker', 'compose', '--project-directory', str(root), '--env-file', str(env_file), '-f', profile.get('compose_file', str(root / 'docker-compose.yml'))]
        if profile.get('compose_project'):
            command += ['-p', profile['compose_project']]
        subprocess.run(command + ['up', '-d', '--no-deps', '--force-recreate', service], check=True, timeout=120, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        raise ValueError('A managed Sidekiq worker is required')
    loaded = env_file.read_text()
    if not all(key + '=' + json.dumps(value) in loaded for key, value in values.items()):
        raise ValueError('Reporting configuration did not persist')
    return {'status': 'succeeded', 'installation_id': identity, 'credential_sha256': hashlib.sha256(token.encode()).hexdigest(), 'environment_changed': changed}


if __name__ == '__main__':
    try:
        data = json.loads(sys.stdin.read(64001))
        print(json.dumps(configure(data)))
    except Exception as error:
        print(json.dumps({'status': 'failed', 'error_class': type(error).__name__}))
        sys.exit(1)
