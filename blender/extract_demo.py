"""Bounded data-only extraction for an official Blender demo ZIP."""
import json
import os
from pathlib import Path, PurePosixPath
import stat
import sys
import zipfile


def extract(source, destination):
    root = Path(destination).resolve()
    total = 0
    with zipfile.ZipFile(source) as archive:
        entries = archive.infolist()
        if len(entries) > 10000:
            raise ValueError('Demo archive contains too many files')
        for entry in entries:
            name = entry.filename.replace('\\', '/')
            path = PurePosixPath(name)
            if path.is_absolute() or '..' in path.parts or ':' in name or stat.S_ISLNK(entry.external_attr >> 16):
                raise ValueError('Demo archive contains an unsafe path')
            total += entry.file_size
            if total > 2 * 1024**3:
                raise ValueError('Demo archive exceeds the extraction limit')
            target = root.joinpath(*path.parts)
            if entry.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(entry) as incoming, open(target, 'wb') as outgoing:
                written = 0
                while True:
                    chunk = incoming.read(1024*1024)
                    if not chunk:
                        break
                    written += len(chunk)
                    if written > entry.file_size:
                        raise ValueError('Demo archive entry exceeds its declared size')
                    outgoing.write(chunk)
    files = sorted(str(path) for path in root.rglob('*.blend') if '__MACOSX' not in path.parts)
    if not files:
        raise ValueError('Demo archive contains no Blender file')
    return files


if __name__ == '__main__':
    print(json.dumps(extract(sys.argv[1], sys.argv[2])))
