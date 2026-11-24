#!/usr/bin/python3 -I
"""Dedicated Debian-APT installer. Install under a root-owned, fixed path."""
import fcntl
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile

POLICY = Path("/etc/lightek/endpoint-patch-target")
TARGET = re.compile(r"([a-z0-9][a-z0-9+.-]{1,127})=([0-9][a-zA-Z0-9.+:~\-]{0,127})\Z")
ENV = {"PATH": "/usr/sbin:/usr/bin:/sbin:/bin", "LC_ALL": "C", "DEBIAN_FRONTEND": "noninteractive"}


def run(*args, cwd=None, timeout=420):
    return subprocess.run(args, cwd=cwd, env=ENV, stdin=subprocess.DEVNULL, capture_output=True,
                          text=True, timeout=timeout, check=True)


def installed_version(package):
    line = run("/usr/bin/dpkg-query", "-W", "-f=${db:Status-Abbrev} ${Version}", package).stdout
    status, _, version = line.strip().partition(" ")
    if not status.startswith("ii") or not version:
        raise ValueError("Package is not installed")
    return version


def deployment(target):
    """Apply a locally authorized exact package version and re-query dpkg."""
    match = TARGET.fullmatch(target)
    if not match or os.geteuid() != 0:
        return {"status": "unavailable"}
    package, requested = match.groups()
    try:
        parent = POLICY.parent.stat(follow_symlinks=False)
        if not stat.S_ISDIR(parent.st_mode) or parent.st_uid != 0 or parent.st_mode & 0o022:
            return {"status": "unavailable"}
        metadata = POLICY.stat(follow_symlinks=False)
        if (metadata.st_uid != 0 or metadata.st_mode & 0o022 or not stat.S_ISREG(metadata.st_mode)
                or metadata.st_size > 256 or POLICY.read_text(encoding="ascii").strip() != target):
            return {"status": "unavailable"}
        before = installed_version(package)
        if before != requested:
            run("/usr/bin/dpkg", "--compare-versions", before, "lt", requested)
            simulation = run("/usr/bin/apt-get", "-s", "--no-remove", "--only-upgrade",
                             "--no-install-recommends", "install", target).stdout.splitlines()
            changes = [line.split()[1].split(":")[0] for line in simulation
                       if line.startswith(("Inst ", "Conf ", "Remv ", "Purg "))]
            if set(changes) != {package} or any(line.startswith(("Remv ", "Purg ")) for line in simulation):
                return {"status": "unavailable"}
            with tempfile.TemporaryDirectory(prefix="lightek-patch-") as directory:
                run("/usr/bin/apt-get", "-o", "APT::Get::AllowUnauthenticated=false", "download", target, cwd=directory)
                artifacts = list(Path(directory).glob("*.deb"))
                if len(artifacts) != 1:
                    return {"status": "failed"}
                artifact = str(artifacts[0])
                if (run("/usr/bin/dpkg-deb", "-f", artifact, "Package").stdout.strip() != package
                        or run("/usr/bin/dpkg-deb", "-f", artifact, "Version").stdout.strip() != requested):
                    return {"status": "failed"}
                run("/usr/bin/dpkg", "--refuse-downgrade", "--force-confold", "--install", artifact, timeout=None)
        after = installed_version(package)
        if after != requested:
            return {"status": "failed"}
        return {"status": "installed", "target": package + "=" + after}
    except (OSError, subprocess.SubprocessError, ValueError):
        return {"status": "failed"}


if __name__ == "__main__":
    target = sys.stdin.readline(257).rstrip("\n")
    try:
        with open("/run/lightek-apt-patch.lock", "a", encoding="ascii") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            print(json.dumps(deployment(target)))
    except OSError:
        print(json.dumps({"status": "unavailable"}))
