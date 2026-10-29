#!/usr/bin/env python3
"""Create or rotate a local Lightek virtual mailbox, without printing its secret."""
import argparse
import os
from pathlib import Path
import pwd
import re
import subprocess
import sys
import tempfile

USERS = Path("/etc/dovecot/lightek-users")
ROOT = Path("/var/vmail")

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--address", required=True)
    p.add_argument("--password-file", required=True)
    args = p.parse_args()
    address = args.address.lower()
    if not re.fullmatch(r"[a-z0-9][a-z0-9._+-]{0,63}@[a-z0-9-]+(?:\.[a-z0-9-]+)+", address):
        raise ValueError("Invalid mailbox address")
    if os.geteuid() != 0:
        raise PermissionError("Run as root")
    secret_path = Path(args.password_file)
    if secret_path.is_symlink() or secret_path.stat().st_mode & 0o077:
        raise ValueError("Password file must be private and not a symlink")
    password = secret_path.read_text().strip()
    if len(password) < 20:
        raise ValueError("Mailbox password must contain at least 20 characters")
    hashed = subprocess.run(["doveadm", "pw", "-s", "SHA512-CRYPT", "-p", password], check=True, capture_output=True, text=True).stdout.strip()
    rows = USERS.read_text().splitlines()
    row = address + ":" + hashed
    rows = [existing for existing in rows if not existing.startswith(address + ":")]
    rows.append(row)
    descriptor, tmp = tempfile.mkstemp(prefix=".lightek-users-", dir=str(USERS.parent))
    try:
        with os.fdopen(descriptor, "w") as stream:
            stream.write("\n".join(rows) + "\n")
        os.chmod(tmp, 0o600)
        os.replace(tmp, USERS)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
    domain, local = address.split("@", 1)[1], address.split("@", 1)[0]
    destination = ROOT / domain / local / "Maildir"
    if destination.is_symlink():
        raise ValueError("Mailbox directory cannot be a symlink")
    for sub in ("cur", "new", "tmp"):
        (destination / sub).mkdir(mode=0o700, parents=True, exist_ok=True)
    owner = pwd.getpwnam("vmail")
    for directory in (ROOT / domain, ROOT / domain / local, destination, *(destination / x for x in ("cur", "new", "tmp"))):
        os.chown(directory, owner.pw_uid, owner.pw_gid)
        os.chmod(directory, 0o700)
    # Publish only explicitly provisioned recipients into Postfix maps.
    mappings = (
        (Path("/etc/postfix/lightek_domains"), domain, "OK"),
        (Path("/etc/postfix/lightek_recipients"), address, "OK"),
    )
    for path, key, value in mappings:
        current = path.read_text().splitlines()
        if not any(line.split()[:1] == [key] for line in current if line.strip() and not line.lstrip().startswith("#")):
            with path.open("a") as handle:
                handle.write(key + " " + value + "\n")
        subprocess.run(["postmap", str(path)], check=True)
    subprocess.run(["postfix", "reload"], check=True)
    print("LIGHTEK_MAILBOX_CONFIGURED=" + address)

if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, PermissionError, subprocess.CalledProcessError) as error:
        print("Mailbox provisioning stopped: " + type(error).__name__, file=sys.stderr)
        sys.exit(1)
