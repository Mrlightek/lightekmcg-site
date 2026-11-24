#!/usr/bin/python3 -I
"""Run as the fixed, locally installed macOS update broker."""
import fcntl
import json
import os
from pathlib import Path
import plistlib
import re
import stat
import subprocess
import sys

POLICY = Path("/etc/lightek/endpoint-macos-patch-target")
TARGET = re.compile(r"([A-Za-z0-9][A-Za-z0-9 ()_.+-]{0,119})\|([A-Za-z0-9][A-Za-z0-9.-]{0,79})\|([A-Za-z0-9][A-Za-z0-9.-]{0,49})\Z")
ENV = {"PATH": "/usr/bin:/usr/sbin:/bin:/sbin", "LC_ALL": "C"}


def run(*argv, timeout=180):
    return subprocess.run(argv, stdin=subprocess.DEVNULL, capture_output=True,
                          check=True, env=ENV, timeout=timeout).stdout


def installed_version(receipt):
    if receipt == "macos-build":
        return run("/usr/bin/sw_vers", "-buildVersion").decode("ascii").strip()
    try:
        result = run("/usr/sbin/pkgutil", "--pkg-info-plist", receipt)
    except subprocess.CalledProcessError:
        return None
    info = plistlib.loads(result)
    if info.get("pkgid") == receipt:
        return info.get("pkg-version")
    return None


def deploy(target):
    match = TARGET.fullmatch(target)
    if not match or sys.platform != "darwin" or os.geteuid() != 0:
        return {"status": "unavailable"}
    label, receipt, expected = match.groups()
    try:
        parent = POLICY.parent.lstat()
        item = POLICY.lstat()
        if (not stat.S_ISDIR(parent.st_mode) or parent.st_uid != 0 or parent.st_mode & 0o022
                or not stat.S_ISREG(item.st_mode) or item.st_uid != 0 or item.st_mode & 0o022
                or item.st_size > 256 or POLICY.read_text(encoding="ascii").strip() != target):
            return {"status": "unavailable"}
        if installed_version(receipt) == expected:
            return {"status": "installed", "target": target}
        catalog = run("/usr/sbin/softwareupdate", "--list").decode("utf-8", errors="replace")
        labels = [line.strip()[8:].strip() for line in catalog.splitlines()
                  if line.strip().startswith("* Label:")]
        if labels.count(label) != 1:
            return {"status": "unavailable"}
        output = run("/usr/sbin/softwareupdate", "--install", label, timeout=None)
        if installed_version(receipt) == expected:
            return {"status": "installed", "target": target}
        return {"status": "pending_restart" if receipt == "macos-build" and b"restart" in output.lower() else "failed"}
    except (OSError, ValueError, subprocess.SubprocessError, plistlib.InvalidFileException):
        return {"status": "failed"}


if __name__ == "__main__":
    target = sys.stdin.readline(257).rstrip("\n")
    try:
        with open("/var/run/lightek-macos-patch.lock", "a", encoding="ascii") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            print(json.dumps(deploy(target)))
    except OSError:
        print(json.dumps({"status": "unavailable"}))
