#!/usr/bin/env python3
"""Connect an existing native installation to the central reservation broker."""
import json
import os
import pathlib
import pwd
import re
import subprocess
import sys
import tempfile

RUNNER = r'''
require "json"
c = JSON.parse(STDIN.read)
site = DymondSite::Site.find_by!(host: c.fetch("domain"))
raise "Installation owner mismatch" unless site.tenant.is_a?(User) && site.tenant.email_address == c.fetch("owner_email")
connection = c.fetch("connection")
slug = "reservation-federation-#{connection.fetch('key')}"
LightekVault::Service.store!(name: "Lightek reservation network", slug: slug,
  payload: {"token" => connection.fetch("token")}, provider: "lightek", purpose: "reservation_federation",
  access_policy: {"consumers" => ["LightekReservations::Federation::Client"], "purposes" => ["reservation_federation"]},
  requested_by: site.tenant.email_address)
site.with_lock do
  site.update!(manifest: site.manifest.to_h.merge("lightek_reservation_federation" => {
    "origin" => connection.fetch("origin"), "key" => connection.fetch("key"), "credential_slug" => slug}))
end
puts "LIGHTEK_FEDERATION=" + JSON.generate({status: "connected", key: connection.fetch("key")})
'''


def apply(config):
    if not re.fullmatch(r"[a-z0-9][a-z0-9.-]+", config["domain"]):
        raise ValueError("Invalid hostname")
    connection = config["connection"]
    if not re.fullmatch(r"[0-9a-f-]{36}", connection["key"]) or not connection["token"].startswith(connection["key"] + "."):
        raise ValueError("Invalid peer identity")
    profile = config["deployment"]
    for key in ("app_root", "env_file", "ruby_bin"):
        value = profile[key]
        if not isinstance(value, str) or not re.fullmatch(r"/[A-Za-z0-9_./ -]+", value) or ".." in value.split("/"):
            raise ValueError("Invalid runtime path")
    if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]*", profile["app_user"]):
        raise ValueError("Invalid runtime user")
    user = pwd.getpwnam(profile["app_user"])
    with tempfile.TemporaryDirectory(prefix="lightek-peer-") as directory:
        path = pathlib.Path(directory)
        os.chown(path, user.pw_uid, user.pw_gid)
        script = path / "connect.rb"
        script.write_text(RUNNER)
        script.chmod(0o600)
        os.chown(script, user.pw_uid, user.pw_gid)
        command = ["sudo", "-u", user.pw_name, "-H", "env", "-u", "GEM_HOME", "-u", "GEM_PATH",
                   "PATH=" + profile["ruby_bin"] + ":/usr/local/bin:/usr/bin:/bin", "bash", "-c",
                   'set -e; set -a; . "$2"; set +a; cd "$1"; exec bundle exec rails runner "$3"',
                   "reservation-peer", profile["app_root"], profile["env_file"], str(script)]
        result = subprocess.run(command, input=json.dumps(config).encode(), stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, check=True, timeout=300)
        return json.loads(next(line.removeprefix("LIGHTEK_FEDERATION=") for line in result.stdout.decode().splitlines()
                               if line.startswith("LIGHTEK_FEDERATION=")))

if __name__ == "__main__":
    try:
        print(json.dumps(apply(json.load(sys.stdin))))
    except Exception as error:
        print(json.dumps({"status": "failed", "error_class": type(error).__name__}))
        sys.exit(1)
