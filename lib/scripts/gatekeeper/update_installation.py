#!/usr/bin/env python3
"""Update an existing managed site from a digest. Configuration arrives only on stdin."""
import contextlib
import fcntl
import json
import os
import pathlib
import re
import signal
import subprocess
import sys
import tempfile
import time
import urllib.request


def validate(config):
    domain = config["domain"]
    if len(domain) > 253 or not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+", domain):
        raise ValueError("Invalid domain")
    if not re.fullmatch(r"[a-f0-9]{40}", config["source_sha"]):
        raise ValueError("Invalid source revision")
    if not re.fullmatch(r"ghcr\.io/[a-z0-9][a-z0-9._/-]*@sha256:[a-f0-9]{64}", config["image"]):
        raise ValueError("Use a GHCR image pinned by digest")
    if type(config["backward_compatible"]) is not bool:
        raise ValueError("Compatibility must be explicit")
    if any(type(config[key]) is not int or config[key] < 1 for key in ("target_id", "attempt")):
        raise ValueError("Invalid attempt identity")
    return config


def environment(text):
    return dict(line.split("=", 1) for line in text.splitlines() if "=" in line and not line.startswith("#"))


def env_value(values, key):
    value = values[key]
    return json.loads(value) if value.startswith('"') else value


def atomic_write(path, text):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(text)
    temporary.chmod(0o600)
    temporary.replace(path)


class Updater:
    def __init__(self, config, base=pathlib.Path("/opt/lightek-sites")):
        self.config = validate(config)
        self.root = base / config["domain"]
        self.env_path = self.root / ".env"
        self.override = self.root / "fleet-image.json"
        self.receipt = {"domain": config["domain"], "source_sha": config["source_sha"],
                        "image": config["image"], "target_id": config["target_id"], "attempt": config["attempt"]}
        self.docker_env = dict(os.environ)

    def run(self, args, **kwargs):
        # Only the final receipt goes to stdout; raw process output stays remote.
        with self.log_path.open("ab") as log:
            return subprocess.run(args, check=True, stdout=log, stderr=log,
                                  env=self.docker_env, timeout=900, **kwargs)

    def compose_args(self):
        command = ["docker", "compose", "--env-file", str(self.env_path), "-p", self.project,
                   "-f", str(self.root / "compose.yml")]
        if self.override.exists():
            command += ["-f", str(self.override)]
        return command

    def compose(self, *args):
        return self.run(self.compose_args() + list(args), cwd=self.root)

    def verify_runtime(self, expected):
        for service in ("web", "worker"):
            container = subprocess.check_output(self.compose_args() + ["ps", "--all", "--quiet", service],
                env=self.docker_env, cwd=self.root, text=True, timeout=30).strip()
            if not container or "\n" in container:
                raise ValueError("Expected one managed container for " + service)
            state = subprocess.check_output(["docker", "inspect", "--format", "{{.Config.Image}} {{.State.Running}}", container],
                env=self.docker_env, text=True, timeout=30).strip()
            if state != self.config["image"] + " true":
                raise ValueError("Running image does not match release for " + service)
        return self.healthy(expected)

    def healthy(self, expected):
        url = "https://" + self.config["domain"] + "/__lightek/website-health"
        # A redirect could hide stale/wrong routing. TLS and the exact release are verified.
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, *args, **kwargs):
                return None
        opener = urllib.request.build_opener(NoRedirect())
        with opener.open(urllib.request.Request(url, headers={"Cache-Control": "no-cache"}), timeout=10) as response:
            health = json.loads(response.read(32768))
            if response.status != 200 or health.get("domain") != self.config["domain"] or health.get("release") != expected or health.get("sections", 0) < 1:
                raise ValueError("Public health does not match the requested release")
            return health

    def execute(self):
        managed = json.loads((self.root / "managed.json").read_text())
        if managed["domain"] != self.config["domain"]:
            raise ValueError("Installation ownership mismatch")
        self.project = managed["project"]
        if not re.fullmatch(r"lt_[a-f0-9]{16}", self.project):
            raise ValueError("Invalid managed Compose project")
        old_env = self.env_path.read_text()
        values = environment(old_env)
        if env_value(values, "LIGHTEK_DEPLOYED_SITE_HOST") != self.config["domain"] or env_value(values, "PROJECT") != self.project:
            raise ValueError("Environment ownership mismatch")
        previous = env_value(values, "LIGHTEK_RELEASE")
        self.receipt["previous_version"] = previous
        old_override = self.override.read_text() if self.override.exists() else None
        old_current = (self.root / "current-release").read_text()
        backups = self.root / "backups"
        backups.mkdir(mode=0o700, exist_ok=True)
        stem = "fleet-{}-{}".format(self.config["target_id"], self.config["attempt"])
        self.log_path = backups / (stem + ".log")
        self.log_path.touch(mode=0o600, exist_ok=True)
        self.receipt_path = backups / (stem + ".json")
        if previous == self.config["source_sha"] and old_override:
            image = json.loads(old_override)["services"]["web"]["image"]
            if image == self.config["image"]:
                try:
                    self.verify_runtime(previous)
                except Exception:
                    pass  # Reconcile settings whose previous restart never completed.
                else:
                    self.receipt.update(status="succeeded", already_current=True)
                    atomic_write(self.receipt_path, json.dumps(self.receipt))
                    return self.receipt
        atomic_write(backups / (stem + ".env"), old_env)
        if old_override:
            atomic_write(backups / (stem + "-image.json"), old_override)
        migrated = False
        switched = False
        try:
            with tempfile.TemporaryDirectory(prefix="lightek-registry-") as auth:
                # A private registry read token never enters .env, receipts or images.
                registry = self.config.get("registry")
                if registry:
                    self.docker_env["DOCKER_CONFIG"] = auth
                    self.run(["docker", "login", "ghcr.io", "--username", registry["username"], "--password-stdin"],
                             input=registry["password"].encode())
                self.run(["docker", "pull", self.config["image"]])
                revision = subprocess.check_output(["docker", "image", "inspect", "--format",
                    '{{ index .Config.Labels "org.opencontainers.image.revision" }}', self.config["image"]],
                    env=self.docker_env, text=True, timeout=30).strip()
                if revision != self.config["source_sha"]:
                    raise ValueError("Image revision label does not match release provenance")
            # Existing volumes, ports, DB secrets, certificate and site content are retained.
            new_env = "\n".join("LIGHTEK_RELEASE=" + json.dumps(self.config["source_sha"]) if line.startswith("LIGHTEK_RELEASE=") else line
                                for line in old_env.splitlines()) + "\n"
            atomic_write(self.env_path, new_env)
            atomic_write(self.override, json.dumps({"services": {
                "web": {"image": self.config["image"]}, "worker": {"image": self.config["image"]}}}))
            switched = True
            # Quiesce jobs before taking the recovery snapshot or migrating schema.
            self.compose("stop", "web", "worker")
            backup = backups / (stem + ".sql")
            # Direct stdout avoids shell pipelines that could conceal pg_dump failure.
            with backup.open("wb") as stream:
                backup.chmod(0o600)
                command = ["docker", "compose", "--env-file", str(self.env_path), "-p", self.project,
                           "-f", str(self.root / "compose.yml"), "exec", "-T", "db", "sh", "-c",
                           'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB"']
                subprocess.run(command, stdout=stream, stderr=subprocess.DEVNULL, check=True, timeout=600, cwd=self.root)
            if backup.stat().st_size == 0:
                raise ValueError("Empty database backup")
            self.receipt["database_backup"] = str(backup)
            # All DB/worker writes are stopped during schema transitions.
            migrated = True  # even a failed migration can have committed preceding migrations
            self.compose("run", "--rm", "-T", "--no-deps", "web", "bin/rails", "db:migrate")
            self.compose("run", "--rm", "-T", "--no-deps", "web", "bin/rails", "assets:precompile")
            self.compose("up", "-d", "--no-deps", "--pull", "never", "web", "worker")
            for attempt in range(24):
                try:
                    self.verify_runtime(self.config["source_sha"])
                    break
                except Exception:
                    if attempt == 23:
                        raise
                    time.sleep(5)
            atomic_write(self.root / "current-release", self.config["source_sha"] + "\n")
            self.receipt.update(status="succeeded", verified_at=time.time())
        except BaseException:
            self.receipt.update(status="failed", migration_started=migrated)
            if switched and (not migrated or self.config["backward_compatible"]):
                atomic_write(self.env_path, old_env)
                if old_override is None:
                    self.override.unlink(missing_ok=True)
                else:
                    atomic_write(self.override, old_override)
                atomic_write(self.root / "current-release", old_current)
                try:
                    self.compose("up", "-d", "--no-deps", "--pull", "never", "web", "worker")
                    self.healthy(previous)
                    self.receipt["code_restored"] = True
                except Exception:
                    self.receipt["code_restored"] = False
            # Never restore a DB automatically: it may contain newer customer writes.
            atomic_write(self.receipt_path, json.dumps(self.receipt))
            raise
        atomic_write(self.receipt_path, json.dumps(self.receipt))
        return self.receipt


def main():
    os.umask(0o077)
    if os.geteuid() != 0:
        raise PermissionError("Root SSH target required")
    config = validate(json.load(sys.stdin))
    def interrupted(*_):
        raise TimeoutError("Remote execution deadline")
    signal.signal(signal.SIGTERM, interrupted)
    # Share the installer's lock so provisioning/redeploy and updates cannot overlap.
    with open("/var/lock/lightek-site-" + config["domain"] + ".lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        updater = Updater(config)
        try:
            print(json.dumps(updater.execute()))
        except BaseException as error:
            updater.receipt.update(status="failed", error_class=type(error).__name__)
            print(json.dumps(updater.receipt))
            raise


if __name__ == "__main__":
    try:
        main()
    except BaseException as error:
        print(json.dumps({"status": "failed", "error_class": type(error).__name__}), file=sys.stderr)
        sys.exit(1)
