#!/usr/bin/env python3
"""Install the package helper for the same app user as the native deployment."""
import argparse
import os
import pathlib
import pwd
import re
import shutil
import subprocess
import tempfile


def install(app_root, app_user, system_root=pathlib.Path("/")):
    if os.geteuid() != 0:
        raise ValueError('Installer must run as root')
    user = pwd.getpwnam(app_user)
    if user.pw_uid == 0 or not re.fullmatch(r'[a-z_][a-z0-9_-]{0,31}', app_user):
        raise ValueError('Choose the unprivileged application user')
    if 'ID=ubuntu' not in (system_root / 'etc/os-release').read_text().splitlines():
        return {'supported': False, 'reason': 'APT integration requires Ubuntu'}
    source = app_root.resolve() / 'lib/scripts/nevaeh/package_control.py'
    if not source.is_file() or source.is_symlink():
        raise ValueError('Pinned package helper source is missing')
    # Ubuntu normally ships python3-apt; install it only if absent.
    check = subprocess.run(['/usr/bin/python3', '-I', '-c', 'import apt'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if check.returncode:
        subprocess.run(['/usr/bin/apt-get', '-y', '--no-remove', 'install', 'python3-apt'], check=True, env={'PATH':'/usr/sbin:/usr/bin:/sbin:/bin','DEBIAN_FRONTEND':'noninteractive'})
    target = system_root / 'usr/local/sbin/lightek-package-control'
    target.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as temp:
        temp.write(source.read_bytes()); temporary = pathlib.Path(temp.name)
    os.chown(temporary, 0, 0); temporary.chmod(0o755); os.replace(temporary, target)
    sudoers = system_root / ('etc/sudoers.d/lightek-nevaeh-packages-' + app_user)
    sudoers.parent.mkdir(parents=True, exist_ok=True)
    rule = app_user + ' ALL=(root) NOPASSWD: /usr/local/sbin/lightek-package-control ""\n'
    # Empty argument specification: the request travels only through bounded stdin.
    with tempfile.NamedTemporaryFile(mode='w', delete=False) as temp:
        temp.write(rule); temporary = pathlib.Path(temp.name)
    try:
        temporary.chmod(0o440)
        subprocess.run(['/usr/sbin/visudo', '-cf', str(temporary)], check=True, stdout=subprocess.DEVNULL)
        shutil.copyfile(temporary, sudoers); os.chown(sudoers, 0, 0); sudoers.chmod(0o440)
    finally:
        temporary.unlink(missing_ok=True)
    return {'supported': True, 'helper': str(target), 'app_user': app_user}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--app-root', type=pathlib.Path, required=True)
    parser.add_argument('--app-user', required=True)
    args = parser.parse_args()
    print(install(args.app_root, args.app_user))
