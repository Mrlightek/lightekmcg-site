#!/usr/bin/env python3
"""Install the root-owned local genesis helper and its single-command sudo policy."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def install(app_root, app_user, system_root=Path('/')):
    if not re.fullmatch(r'[a-z_][a-z0-9_-]*', app_user):
        raise ValueError('Invalid application OS user')
    root = Path(system_root)
    helper = root / 'usr/local/lib/lightek/install_studio_ai.py'
    helper.parent.mkdir(parents=True, exist_ok=True)
    if helper.parent.is_symlink() or helper.is_symlink():
        raise ValueError('Genesis helper must use a root-owned regular path')
    os.chown(helper.parent,0,0)
    helper.parent.chmod(0o755)
    source = Path(app_root) / 'lib/scripts/gatekeeper/install_studio_ai.py'
    # The web account cannot replace the program executed with root privileges.
    shutil.copyfile(source, helper)
    os.chown(helper, 0, 0)
    helper.chmod(0o700)
    catalog = helper.parent / 'studio-ai-packages.json'
    if catalog.is_symlink():
        raise ValueError('Genesis catalog must not be a symlink')
    shutil.copyfile(Path(app_root) / 'config/studio_ai/packages.json', catalog)
    os.chown(catalog, 0, 0)
    catalog.chmod(0o600)
    policy = root / f'etc/sudoers.d/lightek-studio-ai-{app_user}'
    policy.parent.mkdir(parents=True, exist_ok=True)
    if policy.is_symlink():
        raise ValueError('Genesis sudo policy must not be a symlink')
    command = '/usr/bin/timeout --signal=TERM --kill-after=30s 7200s /usr/bin/python3 /usr/local/lib/lightek/install_studio_ai.py'
    text = f'{app_user} ALL=(root) NOPASSWD: {command}\n'
    handle, name = tempfile.mkstemp(prefix='lightek-genesis-policy-')
    try:
        with os.fdopen(handle, 'w') as output:
            output.write(text)
        os.chmod(name, 0o440)
        subprocess.run(['visudo', '-cf', name], check=True, capture_output=True)
        shutil.copyfile(name, policy)
        os.chown(policy, 0, 0)
        policy.chmod(0o440)
    finally:
        os.unlink(name)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app-root', required=True)
    parser.add_argument('--app-user', required=True)
    args = parser.parse_args()
    install(args.app_root, args.app_user)
    print('LIGHTEK_STUDIO_AI_ACCESS_READY=1')
