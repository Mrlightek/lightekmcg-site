#!/usr/bin/env python3
"""Prepare the private HTTP ingress credential; do not alter live SMTP routing."""
import argparse
import grp
import json
import os
from pathlib import Path
import pwd
import re
import secrets
import shutil
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--env-file", default="/etc/lightek/lightekmcg-site.env")
    parser.add_argument("--app-user", default="lightek")
    parser.add_argument("--config-file", default="/etc/lightek/mail-ingress.json")
    parser.add_argument("--backup-directory", default="/var/backups/lightek-mail")
    parser.add_argument("--url", default="https://lightekmcg.com/api/lightek-mail/inbound")
    args = parser.parse_args()
    if os.geteuid() != 0:
        raise SystemExit("Run as root on the central mail server.")
    if not re.fullmatch(r"https://[a-zA-Z0-9.-]+/api/lightek-mail/inbound", args.url):
        raise SystemExit("Use the central application's HTTPS ingress URL.")
    env = Path(args.env_file)
    if env.is_symlink() or not env.is_file():
        raise SystemExit("Production environment file is missing; no changes made.")
    user = pwd.getpwnam(args.app_user)
    content = env.read_text()
    values = re.findall(r"^(?:export )?LIGHTEK_MAIL_INGRESS_TOKEN=([a-f0-9]{64})$", content, re.M)
    if "LIGHTEK_MAIL_INGRESS_TOKEN" in content and not values:
        raise SystemExit("Existing ingress token uses a custom format; preserve it and prepare the pipe credential manually.")
    token = values[-1] if values else secrets.token_hex(32)
    config = Path(args.config_file)
    if config.is_symlink():
        raise SystemExit("Refusing a symlink at the ingress credential path.")
    if config.exists():
        current = json.loads(config.read_text())
        if current != {"url": args.url, "token": token}:
            raise SystemExit("An existing pipe credential differs; no changes made.")
    if not values:
        backup_dir = Path(args.backup_directory) / str(time.time_ns())
        backup_dir.mkdir(parents=True, mode=0o700)
        backup = backup_dir / env.name
        shutil.copy2(env, backup)
        backup.chmod(0o600)
        with env.open("a") as file:
            file.write("\n# Lightek Mail authenticated SMTP-to-HTTPS ingress\nLIGHTEK_MAIL_INGRESS_TOKEN=" + token + "\n")
    config.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(config, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, "w") as file:
        json.dump({"url": args.url, "token": token}, file)
        file.write("\n")
    os.chown(config, user.pw_uid, user.pw_gid)
    config.chmod(0o600)
    print("LIGHTEK_MAIL_INGRESS_CREDENTIAL_PREPARED")
    print("Reload the application and worker through the normal deploy so the new environment is loaded.")
    print("No SMTP routes or mail services were changed. Configure the pipe after reviewing the mail audit.")


if __name__ == "__main__":
    main()
