#!/usr/bin/env python3
"""Reserve native-site identity before bootstrap can leave a partial directory."""
import argparse
import json
import os
from pathlib import Path
import re
import tempfile


def reserve(base, settings, project):
    base = Path(base)
    identity = {'domain': settings['domain'], 'owner_email': settings['owner_email'], 'project': project}
    if base.is_symlink() or base.resolve() != base.absolute():
        raise ValueError('Native site path must not traverse a symlink')
    managed = base / 'managed.json'
    if managed.is_symlink():
        raise ValueError('Native ownership record must not be a symlink')
    if managed.exists():
        current = json.loads(managed.read_text())
        keys = identity.keys() if current.get('bootstrap_pending') else ('domain', 'owner_email')
        if any(current.get(key) != identity[key] for key in keys):
            raise ValueError('Native site belongs to another owner, domain or project')
        return
    if base.exists():
        # An interrupted first bootstrap can leave only these empty directories.
        # Never adopt a database, environment, release files or user content.
        if not base.is_dir():
            raise ValueError('Native site path is not a directory')
        for item in base.iterdir():
            if item.name != 'releases' or item.is_symlink() or not item.is_dir():
                raise ValueError('Unowned native site contains existing data')
            for release in item.iterdir():
                if release.is_symlink() or not release.is_dir() or not re.fullmatch(r'[a-f0-9]{20}', release.name) or any(release.iterdir()):
                    raise ValueError('Unowned native site contains an existing release')
    base.mkdir(parents=True, exist_ok=True)
    record = dict(identity, version=2, adapter='native_rails', bootstrap_pending=True)
    handle, name = tempfile.mkstemp(prefix='.managed-', dir=base)
    try:
        with os.fdopen(handle, 'w') as stream:
            json.dump(record, stream)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, managed)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--base', required=True)
    parser.add_argument('--settings', required=True)
    parser.add_argument('--project', required=True)
    args = parser.parse_args()
    reserve(args.base, json.loads(Path(args.settings).read_text()), args.project)


if __name__ == '__main__':
    main()
