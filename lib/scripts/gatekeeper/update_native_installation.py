#!/usr/bin/env python3
"""Pinned Git deployments for native Passenger Rails, Nginx CDN and systemd services.

All profile data arrives on stdin. Rails runs on the host; Compose is used only
for an explicitly configured dependency backup or worker process.
"""
import fcntl
import hashlib
import http.client
import ipaddress
import json
import os
import pathlib
import pwd
import re
import signal
import socket
import ssl
import subprocess
import sys
import time
import urllib.request
from urllib.parse import urlsplit


PATHS = {"app_root", "env_file", "ruby_bin", "compose_file", "backup_hook", "deploy_hook", "verify_hook", "maintenance_hook", "config_file"}
KEYS = PATHS | {"app_user", "health_url", "revision_url", "probe_address", "worker_mode", "worker_service", "cable_service", "compose_project", "db_service", "service_name", "service_action", "backup_strategy"}


def repository_key(value):
    return re.sub(r"^git@([^:]+):", r"https://\1/", value).removesuffix(".git").lower()


def validate(config):
    if config["adapter"] not in ("native_rails", "cdn_nginx", "systemd_service"):
        raise ValueError("Unsupported native adapter")
    if not re.fullmatch(r"[a-f0-9]{40}", config["source_sha"]):
        raise ValueError("An exact source SHA is required")
    if not re.fullmatch(r"(?:https://[a-zA-Z0-9.-]+/|git@[a-zA-Z0-9.-]+:)[a-zA-Z0-9_.-]+/[a-zA-Z0-9_./-]+", config["repository"]) or ".." in config["repository"].split("/"):
        raise ValueError("Invalid repository URL")
    if not re.fullmatch(r"[a-z][a-z0-9_-]{0,79}", config["component"]):
        raise ValueError("Invalid component")
    if not re.fullmatch(r"[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?", config["domain"]):
        raise ValueError("Invalid installation hostname")
    if any(type(config[k]) is not int or config[k] < 1 for k in ("target_id", "attempt")) or type(config["backward_compatible"]) is not bool:
        raise ValueError("Invalid execution identity or compatibility")
    if config["adapter"] == "native_rails" and config["component"] == "lightek_app":
        labels = config["domain"].split(".")
        if len(labels) < 2 or labels[-1].isdigit() or labels[-1] in ("local", "localhost", "internal") or config["domain"].endswith(".home.arpa"):
            raise ValueError("Use a public DNS hostname for the application")
    deployment = config["deployment"]
    if not isinstance(deployment, dict) or set(deployment) - KEYS:
        raise ValueError("Unknown profile fields")
    for key, value in deployment.items():
        if not isinstance(value, str) or re.search(r"[\x00-\x1f]", value):
            raise ValueError("Profile values must be plain strings")
        if not value:
            continue
        if key == "probe_address":
            ipaddress.ip_address(value)
        if key in PATHS and (not value.startswith("/") or ".." in value.split("/")):
            raise ValueError("An absolute path without traversal is required")
        if key in ("health_url", "revision_url"):
            url = urlsplit(value)
            if url.scheme != "https" or url.hostname != config["domain"] or url.username or url.password or url.fragment:
                raise ValueError("HTTPS URL without credentials required")
        if key in ("app_user", "worker_service", "cable_service", "compose_project", "db_service", "service_name") and not re.fullmatch(r"[a-zA-Z0-9_][a-zA-Z0-9_.@-]*", value):
            raise ValueError("Invalid user or service name")
    required = {"app_root", "app_user", "health_url"}
    if config["adapter"] == "native_rails":
        required |= {"ruby_bin", "env_file", "revision_url"}
        mode = deployment.get("worker_mode", "systemd")
        if mode not in ("systemd", "compose", "none"):
            raise ValueError("Unsupported worker mode")
        if mode != "none":
            required.add("worker_service")
        strategy = deployment.get("backup_strategy", "compose")
        if strategy not in ("compose", "hook"):
            raise ValueError("Unsupported backup strategy")
        if strategy == "hook":
            required.add("backup_hook")
    if config["adapter"] == "cdn_nginx":
        required |= {"config_file", "service_name"}
    if config["adapter"] == "systemd_service":
        required.add("service_name")
        if not deployment.get("revision_url") and not deployment.get("verify_hook"):
            raise ValueError("Service requires revision verification")
        if deployment.get("service_action", "restart") not in ("restart", "reload"):
            raise ValueError("Invalid service action")
    if any(not deployment.get(key) for key in required):
        raise ValueError("Incomplete deployment profile")
    return config


def atomic_write(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(value)
    temporary.chmod(0o600)
    temporary.replace(path)


class NativeUpdater:
    def __init__(self, config, state_base=pathlib.Path("/var/lib/lightek/fleet")):
        self.config = validate(config)
        self.profile = config["deployment"]
        self.root = pathlib.Path(self.profile["app_root"]).resolve()
        self.user = pwd.getpwnam(self.profile["app_user"])
        self.state = state_base / hashlib.sha256(str(self.root).encode()).hexdigest()[:24]
        self.state.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.stem = "fleet-{}-{}".format(config["target_id"], config["attempt"])
        self.log = self.state / (self.stem + ".log")
        self.log.touch(mode=0o600, exist_ok=True)
        self.receipt = {key: config[key] for key in ("domain", "source_sha", "target_id", "attempt", "adapter", "component", "repository")}
        self.receipt.update(image=None, log_path=str(self.log))
        self.migration_started = False
        self.execution_sha = config["source_sha"]

    def command(self, args, capture=False, stdout=None):
        with self.log.open("ab") as log:
            result = subprocess.run(args, cwd=self.root, check=True, timeout=900,
                stdout=subprocess.PIPE if capture else (stdout if stdout is not None else log), stderr=log)
            return result.stdout.decode().strip() if capture else None

    def as_user(self, args, capture=False, stdout=None):
        # argv preserves spaces and shell characters; only the administrator's
        # existing environment file is sourced, as in deploy_project.sh.
        binary = self.profile.get("ruby_bin", "/usr/local/bin")
        command = ["sudo", "-u", self.user.pw_name, "-H", "env", "-u", "GEM_HOME", "-u", "GEM_PATH",
            "PATH=" + binary + ":/usr/local/bin:/usr/bin:/bin", "RBENV_ROOT=" + self.user.pw_dir + "/.rbenv",
            "BUNDLE_FROZEN=true",
            "LIGHTEK_TARGET_SHA=" + self.execution_sha, "bash", "-c",
            'set -e; if [ -n "$2" ]; then set -a; . "$2"; set +a; fi; cd "$1"; shift 2; exec "$@"',
            "fleet-run", str(self.root), self.profile.get("env_file", "")] + list(args)
        return self.command(command, capture=capture, stdout=stdout)

    def git(self, *args, capture=False):
        return self.as_user(["git", *args], capture=capture)

    def compose(self, *args, stdout=None):
        command = ["docker", "compose", "--project-directory", str(self.root), "--env-file", self.profile["env_file"],
            "-f", self.profile.get("compose_file", str(self.root / "docker-compose.yml"))]
        if self.profile.get("compose_project"):
            command += ["-p", self.profile["compose_project"]]
        return self.command(command + list(args), stdout=stdout)

    def worker(self, action):
        mode = self.profile.get("worker_mode", "systemd")
        service = self.profile.get("worker_service")
        if mode == "systemd":
            self.command(["systemctl", action, service])
        elif mode == "compose":
            # Only the configured worker is touched, never db/redis/minio.
            self.compose("stop" if action == "stop" else "start", service)

    def backup(self):
        destination = self.state / (self.stem + ".sql")
        with destination.open("wb") as stream:
            destination.chmod(0o600)
            if self.profile.get("backup_strategy", "compose") == "hook":
                self.as_user([self.profile["backup_hook"]], stdout=stream)
            else:
                self.compose("exec", "-T", self.profile.get("db_service", "db"), "sh", "-c",
                    'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB"', stdout=stream)
        if destination.stat().st_size == 0:
            raise ValueError("Empty database backup")
        self.receipt["database_backup"] = str(destination)

    def hook(self, key, *args):
        path = self.profile.get(key)
        if path:
            return self.as_user([path, *args])

    def activate(self):
        if self.config["adapter"] == "native_rails":
            self.command(["apache2ctl", "configtest"])
            self.command(["passenger-config", "restart-app", str(self.root), "--ignore-app-not-running"])
            if self.profile.get("worker_mode", "systemd") != "none":
                self.worker("restart")
            if self.profile.get("cable_service"):
                self.command(["systemctl", "restart", self.profile["cable_service"]])
        elif self.config["adapter"] == "cdn_nginx":
            self.check_nginx()
            self.command(["systemctl", "reload", self.profile["service_name"]])
            self.command(["systemctl", "is-active", "--quiet", self.profile["service_name"]])
        else:
            self.command(["systemctl", self.profile.get("service_action", "restart"), self.profile["service_name"]])
            self.command(["systemctl", "is-active", "--quiet", self.profile["service_name"]])

    def check_nginx(self):
        config_file = pathlib.Path(self.profile["config_file"]).resolve()
        if not config_file.is_relative_to(self.root) or not config_file.is_file():
            raise ValueError("CDN config must be a file inside its registered checkout")
        # nginx -T validates the actual default configuration, and proves that
        # this checkout is included by it. No unrelated vhost/cache is replaced.
        configuration = self.command(["nginx", "-T"], capture=True)
        included = [pathlib.Path(line.removeprefix("# configuration file ").removesuffix(":")).resolve()
            for line in configuration.splitlines() if line.startswith("# configuration file ")]
        if config_file not in included:
            raise ValueError("Registered CDN configuration is not included by Nginx")

    def request(self, url):
        if url == self.profile.get("revision_url"):
            # A load-balanced public hostname may answer from a different
            # customer replica. Verify this instance with the real TLS hostname.
            address = self.profile.get("probe_address", "127.0.0.1")
            class DirectTLS(http.client.HTTPSConnection):
                def connect(connection):
                    sock = socket.create_connection((address, connection.port), timeout=connection.timeout)
                    connection.sock = connection._context.wrap_socket(sock, server_hostname=connection.host)
            parsed = urlsplit(url)
            connection = DirectTLS(parsed.hostname, parsed.port or 443, timeout=10, context=ssl.create_default_context())
            try:
                connection.request("GET", parsed.path + ("?" + parsed.query if parsed.query else ""),
                    headers={"Host": parsed.netloc, "Cache-Control": "no-cache"})
                response = connection.getresponse()
                if response.status != 200:
                    raise ValueError("Instance revision probe failed")
                return response.read(32768)
            finally:
                connection.close()
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, *args, **kwargs):
                return None
        opener = urllib.request.build_opener(NoRedirect())
        with opener.open(urllib.request.Request(url, headers={"Cache-Control": "no-cache"}), timeout=10) as response:
            if response.status != 200:
                raise ValueError("Service health failed")
            return response.read(32768)

    def verify(self, sha):
        if self.git("rev-parse", "HEAD", capture=True) != sha:
            raise ValueError("Checkout revision changed during update")
        self.request(self.profile["health_url"])
        if self.profile.get("revision_url"):
            revision = json.loads(self.request(self.profile["revision_url"]))
            if revision.get("source_sha") != sha:
                raise ValueError("Running service revision does not match the release")
        if self.profile.get("verify_hook"):
            revision = self.as_user([self.profile["verify_hook"]], capture=True)
            if revision != sha:
                raise ValueError("Verification hook did not report the running revision")
        if self.config["adapter"] == "cdn_nginx":
            self.check_nginx()
            self.command(["systemctl", "is-active", "--quiet", self.profile["service_name"]])
        if self.config["adapter"] == "native_rails" and self.profile.get("worker_mode", "systemd") == "systemd":
            self.command(["systemctl", "is-active", "--quiet", self.profile["worker_service"]])
        if self.config["adapter"] == "systemd_service":
            self.command(["systemctl", "is-active", "--quiet", self.profile["service_name"]])

    def execute(self):
        if not (self.root / ".git").exists():
            raise ValueError("Native installation must be an existing Git checkout")
        with (self.state / "update.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return self.deploy()

    def deploy(self):
        remote = self.git("config", "--get", "remote.origin.url", capture=True)
        if repository_key(remote) != repository_key(self.config["repository"]):
            raise ValueError("Repository identity mismatch")
        if self.git("status", "--porcelain", "--untracked-files=no", capture=True):
            raise ValueError("Tracked local changes must be committed before updating")
        previous = self.git("rev-parse", "HEAD", capture=True)
        self.receipt["previous_version"] = previous
        desired = self.config["source_sha"]
        if previous == desired:
            try:
                if self.config["adapter"] == "cdn_nginx":
                    self.activate()  # Reconcile a lost/failed reload acknowledgement.
                self.verify(desired)
            except Exception:
                pass
            else:
                self.receipt.update(status="succeeded", already_current=True)
                self.save_receipt()
                return self.receipt
        expected = self.config.get("expected_previous_sha")
        if expected and re.fullmatch(r"[a-f0-9]{40}", expected) and previous not in (expected, desired):
            raise ValueError("Checkout changed since the last verified installation; inspect its revision before updating")
        self.git("fetch", "--no-tags", "origin", desired)
        if self.git("rev-parse", "FETCH_HEAD", capture=True) != desired:
            raise ValueError("Fetched commit does not match release")
        changed = False
        quiesced = False
        try:
            if self.config["adapter"] == "native_rails":
                quiesced = True
                self.hook("maintenance_hook", "enable")
                self.worker("stop")
                self.backup()
            self.git("checkout", "--detach", desired)
            changed = True
            if self.config["adapter"] == "native_rails":
                self.as_user(["bundle", "install", "--jobs", "1"])
                self.migration_started = True
                self.as_user(["bundle", "exec", "rails", "db:migrate"])
                if self.config["component"] == "lightek_app":
                    self.as_user(["env", "LIGHTEK_EXPECTED_SITE_HOST=" + self.config["domain"], "bundle", "exec", "rails", "lightek:site_binding:verify"])
                self.as_user(["bundle", "exec", "rails", "assets:precompile"])
                self.as_user(["bundle", "exec", "rails", "zeitwerk:check"])
            else:
                self.hook("deploy_hook")
            self.activate()
            if quiesced:
                self.hook("maintenance_hook", "disable")
                quiesced = False
            for attempt in range(24):
                try:
                    self.verify(desired)
                    break
                except Exception:
                    if attempt == 23:
                        raise
                    time.sleep(5)
            self.receipt.update(status="succeeded", verified_at=time.time())
        except BaseException:
            self.receipt.update(status="failed", migration_started=self.migration_started)
            can_restore = not self.migration_started or self.config["backward_compatible"]
            # A service deploy hook can also mutate persistent state.
            if self.config["adapter"] != "native_rails" and self.profile.get("deploy_hook"):
                can_restore = self.config["backward_compatible"]
            if can_restore:
                try:
                    if changed:
                        self.git("checkout", "--detach", previous)
                        self.execution_sha = previous
                        if self.config["adapter"] == "native_rails":
                            self.as_user(["bundle", "install", "--jobs", "1"])
                            self.as_user(["bundle", "exec", "rails", "assets:precompile"])
                        else:
                            self.hook("deploy_hook")
                    self.activate()
                    if quiesced:
                        self.hook("maintenance_hook", "disable")
                        quiesced = False
                    self.verify(previous)
                    self.receipt["code_restored"] = True
                except Exception:
                    self.receipt["code_restored"] = False
            self.save_receipt()
            raise
        self.save_receipt()
        return self.receipt

    def save_receipt(self):
        atomic_write(self.state / (self.stem + ".json"), json.dumps(self.receipt))


def main():
    os.umask(0o077)
    if os.geteuid() != 0:
        raise PermissionError("Root SSH target required for service control")
    def interrupted(*_):
        raise TimeoutError("Native update deadline")
    signal.signal(signal.SIGTERM, interrupted)
    instance = None
    try:
        instance = NativeUpdater(json.load(sys.stdin))
        print(json.dumps(instance.execute()))
    except BaseException as error:
        receipt = instance.receipt if instance else {}
        receipt.update(status="failed", error_class=type(error).__name__)
        if instance:
            instance.save_receipt()
        print(json.dumps(receipt))
        sys.exit(1)


if __name__ == "__main__":
    main()
