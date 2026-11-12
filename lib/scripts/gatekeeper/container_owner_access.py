#!/usr/bin/env python3
"""Issue an expiring owner setup token in an already verified Lightek container."""
import json
import os
import pathlib
import re
import subprocess
import sys

RUNNER = r'''
require "json"
c = JSON.parse(STDIN.read)
user = User.find_by!(email_address: c.fetch("owner_email"))
raise "Owner is not an administrator" unless %w[admin super_admin].include?(user.role)
site = DymondSite::Site.find_by!(host: c.fetch("domain"))
raise "Owner does not own this site" unless site.tenant == user
puts "LIGHTEK_OWNER_ACCESS=" + JSON.generate(token: user.generate_token_for(:password_reset))
'''


def issue(config):
    if not re.fullmatch(r"[a-z0-9][a-z0-9.-]+\.[a-z]+", config.get("domain", "")):
        raise ValueError("Invalid hostname")
    if type(config.get("launch_id")) is not int or config["launch_id"] <= 0:
        raise ValueError("Invalid installation")
    root = pathlib.Path("/opt/lightek-applications") / config["domain"]
    state = json.loads((root / "installation.json").read_text())
    if state["launch_id"] != config["launch_id"] or not state.get("owner_password"):
        raise ValueError("Installation identity mismatch")
    result = subprocess.run(["docker", "compose", "-p", f"lightek-app-{config['launch_id']}", "-f", str(root / "compose.json"),
                             "exec", "-T", "web", "bin/rails", "runner", RUNNER],
                            input=json.dumps(config).encode(), stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True, timeout=60)
    marker = next(line for line in result.stdout.decode().splitlines() if line.startswith("LIGHTEK_OWNER_ACCESS="))
    token = json.loads(marker.split("=", 1)[1])["token"]
    if not isinstance(token, str) or not 32 <= len(token) <= 4096 or re.search(r"[\r\n]", token):
        raise ValueError("Invalid owner token")
    return {"status": "succeeded", "token": token, "domain": config["domain"]}


if __name__ == "__main__":
    try:
        if os.geteuid() != 0:
            raise PermissionError("Root is required")
        print(json.dumps(issue(json.load(sys.stdin))))
    except Exception as error:
        print(json.dumps({"status": "failed", "error_class": type(error).__name__}))
        sys.exit(1)
