#!/usr/bin/env python3
"""Apply a paid reservation package to a registered native Rails installation."""
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
DymondSite::Site.transaction do
  site = DymondSite::Site.find_by!(host: c.fetch("domain"))
  owner = site.tenant
  raise "Reservation owner mismatch" unless owner.is_a?(User) && owner.email_address == c.fetch("owner_email")
  prior = site.manifest.to_h.fetch("lightek_reservation")
  raise "Reservation reference mismatch" unless prior.fetch("reference") == c.fetch("reference")
  plan_data = c.fetch("package").fetch("subscription_plan")
  plan = DymondBank::SubscriptionPlan.find_or_initialize_by(slug: plan_data.fetch("slug"))
  plan.assign_attributes(plan_data.slice("name", "description", "price_monthly_cents", "price_annual_cents", "currency", "features_json"))
  plan.save!
  subscription = DymondBank::Subscription.find_or_initialize_by(subscriber: owner)
  subscription.assign_attributes(plan: plan, status: "active", billing_interval: c.fetch("package").fetch("billing_interval"),
    current_period_start: c.fetch("starts_at"), current_period_end: c.fetch("ends_at"))
  subscription.save!
  updated = c.fetch("package").merge("reference" => c.fetch("reference"), "manage_url" => prior.fetch("manage_url"))
  site.update!(manifest: site.manifest.to_h.merge("lightek_reservation" => updated, "lightek_reservation_change_id" => c.fetch("change_id")))
  puts "LIGHTEK_RESERVATION=" + JSON.generate({reference: c.fetch("reference"), change_id: c.fetch("change_id"), status: "applied"})
end
'''


def validate(config):
    if not re.fullmatch(r"[a-z0-9][a-z0-9.-]+", config["domain"]):
        raise ValueError("Invalid hostname")
    if not re.fullmatch(r"LR-[A-F0-9]{12}", config["reference"]):
        raise ValueError("Invalid reservation reference")
    if type(config["change_id"]) is not int or config["change_id"] <= 0:
        raise ValueError("Invalid change identity")
    profile = config["deployment"]
    for key in ("app_root", "env_file", "ruby_bin"):
        value = profile[key]
        if not isinstance(value, str) or not re.fullmatch(r"/[A-Za-z0-9_./ -]+", value) or ".." in value.split("/"):
            raise ValueError("Invalid runtime path")
    if not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]*", profile["app_user"]):
        raise ValueError("Invalid runtime user")
    return config


def apply(config):
    validate(config)
    profile = config["deployment"]
    user = pwd.getpwnam(profile["app_user"])
    with tempfile.TemporaryDirectory(prefix="lightek-reservation-") as directory:
        path = pathlib.Path(directory)
        os.chown(path, user.pw_uid, user.pw_gid)
        script = path / "apply.rb"
        script.write_text(RUNNER)
        script.chmod(0o600)
        os.chown(script, user.pw_uid, user.pw_gid)
        command = ["sudo", "-u", user.pw_name, "-H", "env", "-u", "GEM_HOME", "-u", "GEM_PATH",
                   "PATH=" + profile["ruby_bin"] + ":/usr/local/bin:/usr/bin:/bin", "bash", "-c",
                   'set -e; set -a; . "$2"; set +a; cd "$1"; exec bundle exec rails runner "$3"',
                   "reservation-sync", profile["app_root"], profile["env_file"], str(script)]
        result = subprocess.run(command, input=json.dumps(config).encode(), stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, check=True, timeout=300)
        return json.loads(next(line.removeprefix("LIGHTEK_RESERVATION=") for line in result.stdout.decode().splitlines()
                               if line.startswith("LIGHTEK_RESERVATION=")))


if __name__ == "__main__":
    try:
        print(json.dumps(apply(json.load(sys.stdin))))
    except Exception as error:
        print(json.dumps({"status": "failed", "error_class": type(error).__name__}))
        sys.exit(1)
