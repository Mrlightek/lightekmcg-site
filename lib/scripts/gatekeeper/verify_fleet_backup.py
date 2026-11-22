"""Restore a managed fleet snapshot into a disposable PostgreSQL container."""

import fcntl
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import uuid


HOST = re.compile(r"[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)+")
IMAGE = "postgres:16-bookworm"
MAX_BYTES = 512 * 1024 * 1024
RESTORE = """
mkdir /work/data /work/socket
initdb -D /work/data -A trust --no-locale >/dev/null
pg_ctl -D /work/data -l /work/postgres.log -o "-c listen_addresses='' -k /work/socket" -w start >/dev/null
psql -X -q --set ON_ERROR_STOP=1 --single-transaction --host /work/socket --dbname postgres >/dev/null
psql -XqAt --set ON_ERROR_STOP=1 --host /work/socket --dbname postgres \
  -c 'SELECT count(*) FROM public.schema_migrations'
"""


def restore(payload, base=Path("/opt/lightek-sites")):
    domain, target_id, attempt = (payload[key] for key in ("domain", "target_id", "attempt"))
    if not isinstance(domain, str) or len(domain) > 253 or not HOST.fullmatch(domain):
        raise ValueError("Invalid installation domain")
    if not all(type(number) is int and number > 0 for number in (target_id, attempt)):
        raise ValueError("Invalid snapshot identity")
    root = base / domain
    backups = root / "backups"
    if backups.resolve(strict=True) != backups or json.loads((root / "managed.json").read_text())["domain"] != domain:
        raise ValueError("Installation path or identity changed")
    snapshot = backups / f"fleet-{target_id}-{attempt}.sql"
    container = f"lightek-restore-{uuid.uuid4().hex}"

    descriptor = os.open(snapshot, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(descriptor, "rb") as dump:
        info = os.fstat(dump.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.geteuid() or info.st_mode & 0o077 or not 0 < info.st_size <= MAX_BYTES:
            raise ValueError("Snapshot must be a private regular file within the drill limit")
        image = subprocess.check_output(["docker", "image", "inspect", "--format", "{{.Id}}", IMAGE],
                                        stderr=subprocess.DEVNULL, text=True, timeout=15).strip()
        if not re.fullmatch(r"sha256:[0-9a-f]{64}", image):
            raise ValueError("Local managed database image missing")
        try:
            result = subprocess.run(
                ["docker", "run", "--name", container, "--rm", "-i", "--pull", "never", "--network", "none",
                 "--read-only", "--tmpfs", "/work:rw,nosuid,nodev,size=1g,mode=1777", "--memory", "768m",
                 "--cpus", "1", "--pids-limit", "96", "--cap-drop", "ALL", "--security-opt", "no-new-privileges",
                 "--user", "postgres", "--entrypoint", "/usr/bin/timeout", image, "600", "/bin/sh", "-eu", "-c", RESTORE],
                stdin=dump, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, timeout=650, check=True,
            )
        finally:
            subprocess.run(["docker", "rm", "-f", container], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           timeout=15, check=False)
    count = result.stdout.strip()
    if not count.isdecimal() or int(count) == 0:
        raise ValueError("Restored snapshot has no migration history")
    return {"domain": domain, "target_id": target_id, "attempt": attempt, "status": "succeeded", "restored_schema": True}


def run(payload, base=Path("/opt/lightek-sites")):
    descriptor = os.open(base / ".backup-restore-drill.lock", os.O_CREAT | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
    with os.fdopen(descriptor, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        memory = re.search(r"^MemAvailable:\s+(\d+)\s+kB$", Path("/proc/meminfo").read_text(), re.MULTILINE)
        if not memory or int(memory.group(1)) < 1024 * 1024:
            raise ValueError("The host needs one GiB of available memory for the isolated restore")
        return restore(payload, base)


if __name__ == "__main__":
    try:
        print(json.dumps(run(json.load(sys.stdin))))
    except Exception as error:
        print(json.dumps({"status": "failed", "error_class": type(error).__name__}))
        sys.exit(1)
