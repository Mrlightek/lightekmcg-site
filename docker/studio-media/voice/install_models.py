#!/usr/bin/env python3
"""Fetch fixed, checksum-verified build dependencies; never used during speech."""
import hashlib
from pathlib import Path
import sys
import urllib.request

FILES = {
    'model.onnx': ('kokoro-v1.0.int8.onnx', 'ae315a79b623f244700e4afb9246c46a26066782e049ba174bf3ba433970ee9c'),
    'voices.bin': ('voices-v1.0.bin', 'bca610b8308e8d99f32e6fe4197e7ec01679264efed0cac9140fe9c29f1fbf7d'),
}
BASE = 'https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.1/'


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    directory = Path(sys.argv[1])
    directory.mkdir(parents=True, exist_ok=True)
    for name, (source, expected) in FILES.items():
        destination = directory / name
        if destination.is_file() and digest(destination) == expected:
            continue
        temporary = destination.with_suffix('.download')
        try:
            with urllib.request.urlopen(BASE + source, timeout=90) as response, temporary.open('wb') as output:
                size = 0
                while chunk := response.read(1024 * 1024):
                    size += len(chunk)
                    if size > 130_000_000:
                        raise ValueError('Voice dependency exceeds build size limit')
                    output.write(chunk)
            if digest(temporary) != expected:
                raise ValueError('Voice dependency checksum mismatch: ' + name)
            temporary.replace(destination)
        finally:
            temporary.unlink(missing_ok=True)


if __name__ == '__main__':
    main()
