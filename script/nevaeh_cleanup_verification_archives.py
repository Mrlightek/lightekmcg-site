#!/usr/bin/env python3
"""Remove only expired git-archive copies created by Nevaeh verification jobs."""
import os
import re
import shutil
import stat
import time
import sys

completed = set(sys.argv[1:])
if any(not re.fullmatch(r"[0-9a-f]{40}", value) for value in completed):
    raise SystemExit("Invalid completed verification identity")

root = '/var/tmp'
pattern = re.compile(r'lightek-nevaeh-(?:kb|overview|backlog)-[0-9a-f]{40}\Z')
removed = []
for name in os.listdir(root):
    if not pattern.fullmatch(name):
        continue
    path = os.path.join(root, name)
    info = os.lstat(path)
    if not stat.S_ISDIR(info.st_mode) or (time.time() - info.st_mtime < 1800 and name[-40:] not in completed):
        continue
    shutil.rmtree(path)
    removed.append(name)
space = shutil.disk_usage(root)
print('NEVAEH_VERIFICATION_ARCHIVES_REMOVED=' + str(len(removed)))
print('NEVAEH_HOST_AVAILABLE_BYTES=' + str(space.free))
if space.free < 128 * 1024 * 1024:
    raise SystemExit('Host storage remains below 128 MiB after cleaning expired verification copies; operator storage recovery is required')
