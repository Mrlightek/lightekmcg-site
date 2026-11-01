import importlib.util
import io
import json
import os
import pathlib
import pwd
import subprocess
import tempfile
import unittest
from unittest.mock import MagicMock, patch

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("native_updater", ROOT / "lib/scripts/gatekeeper/update_native_installation.py")
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)


def git(path, *args):
    return subprocess.check_output(["git", "-C", str(path), *args], stderr=subprocess.DEVNULL, text=True).strip()


class TestRuntime(native.NativeUpdater):
    """Real Git/filesystem, simulated Rails binaries, Docker dependencies and services."""
    def __init__(self, config, state_base, running_sha):
        super().__init__(config, state_base)
        self.running_sha = running_sha
        self.calls = []
        self.fail = lambda args: False

    def command(self, args, capture=False, stdout=None):
        self.calls.append(args)
        if self.fail(args):
            raise subprocess.CalledProcessError(1, args)
        if stdout is not None:
            stdout.write(b"-- customer PostgreSQL snapshot\n")
        if args == ["nginx", "-T"]:
            return "# configuration file " + self.profile["config_file"] + ":\n# config is included\n"
        if args[:2] == ["passenger-config", "restart-app"] or args[:2] in (["systemctl", "reload"], ["systemctl", "restart"]):
            self.running_sha = git(self.root, "rev-parse", "HEAD")
        return "" if capture else None

    def as_user(self, args, capture=False, stdout=None, input_data=None):
        if args[-1] == "script/nevaeh_apply_lesson_bundle.rb":
            self.calls.append(args)
            self.lesson_input = json.loads(input_data)
            if self.fail(args):
                raise subprocess.CalledProcessError(1, args)
            return "NEVAEH_KNOWLEDGE_BUNDLE=" + json.dumps({"sha256": self.lesson_input["sha256"], "lessons": len(self.lesson_input["lessons"])})
        if args[0] == "git":
            return git(self.root, *args[1:])
        if capture and args[0] == self.profile.get("verify_hook"):
            return self.running_sha
        return self.command(args, capture=capture, stdout=stdout)

    def request(self, url):
        if url == self.profile.get("revision_url"):
            return json.dumps({"source_sha": self.running_sha}).encode()
        return b"healthy"


class FleetNativeUpdaterTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = pathlib.Path(self.temporary.name)
        origin = self.base / "origin.git"
        source = self.base / "source"
        self.app = self.base / "customer"
        subprocess.run(["git", "init", "-q", "--bare", str(origin)], check=True)
        subprocess.run(["git", "clone", "-q", str(origin), str(source)], check=True, stderr=subprocess.DEVNULL)
        git(source, "config", "user.name", "Test Operator")
        git(source, "config", "user.email", "test@example.test")
        (source / "feature.rb").write_text("# previous\n")
        (source / "nginx").mkdir()
        (source / "nginx/site.conf").write_text("# previous cache rules\n")
        git(source, "add", ".")
        git(source, "commit", "-qm", "Initial")
        git(source, "push", "origin", "HEAD")
        subprocess.run(["git", "clone", "-q", str(origin), str(self.app)], check=True)
        self.previous = git(self.app, "rev-parse", "HEAD")
        (source / "feature.rb").write_text("# requested customer feature\n")
        (source / "nginx/site.conf").write_text("# updated cache rules\n")
        git(source, "add", ".")
        git(source, "commit", "-qm", "Feature")
        git(source, "push", "origin", "HEAD")
        self.desired = git(source, "rev-parse", "HEAD")
        repository = "https://example.test/account/software.git"
        git(self.app, "remote", "set-url", "origin", repository)
        git(self.app, "config", "url." + str(origin) + ".insteadOf", repository)
        self.env = self.app / ".env"
        self.env.write_text("SECRET_KEY_BASE=customer-private-key\n")
        self.config = dict(adapter="native_rails", component="lightek_app", domain="customer.example.com", repository=repository,
            source_sha=self.desired, expected_previous_sha=self.previous, target_id=1, attempt=1, backward_compatible=False,
            deployment=dict(app_root=str(self.app), app_user=pwd.getpwuid(os.getuid()).pw_name,
                env_file=str(self.env), ruby_bin="/usr/bin", worker_mode="systemd", worker_service="customer-sidekiq",
                health_url="https://customer.example.com/up", revision_url="https://customer.example.com/__lightek/release"))

    def instance(self, adapter="native_rails", **profile):
        config = dict(self.config, deployment=dict(self.config["deployment"]))
        config["adapter"] = adapter
        if adapter == "cdn_nginx":
            config["component"] = "cdn"
            config["deployment"] = {"app_root": str(self.app), "app_user": self.config["deployment"]["app_user"],
                "health_url": "https://customer.example.com/health", "config_file": str(self.app / "nginx/site.conf"), "service_name": "nginx"}
        if adapter == "systemd_service":
            config["component"] = "realtime"
            config["deployment"] = {"app_root": str(self.app), "app_user": self.config["deployment"]["app_user"],
                "health_url": "https://customer.example.com/health", "service_name": "realtime",
                "deploy_hook": str(self.app / "bin/build-service"), "verify_hook": str(self.app / "bin/running-revision")}
        config["deployment"].update(profile)
        return TestRuntime(config, self.base / "state", self.previous)

    def test_native_rails_updates_checkout_and_passenger_without_containerizing_application(self):
        instance = self.instance()
        receipt = instance.execute()
        self.assertEqual(self.desired, git(self.app, "rev-parse", "HEAD"))
        self.assertEqual("succeeded", receipt["status"])
        self.assertEqual(self.desired, instance.running_sha)
        self.assertIsNone(receipt["image"])
        self.assertEqual("SECRET_KEY_BASE=customer-private-key\n", self.env.read_text())
        self.assertIn(["bundle", "install", "--jobs", "1"], instance.calls)
        self.assertIn(["bundle", "exec", "rails", "db:migrate"], instance.calls)
        binding = ["env", "LIGHTEK_EXPECTED_SITE_HOST=" + instance.config["domain"], "bundle", "exec", "rails", "lightek:site_binding:verify"]
        self.assertIn(binding, instance.calls)
        self.assertLess(instance.calls.index(["bundle", "exec", "rails", "db:migrate"]), instance.calls.index(binding))
        self.assertIn(["passenger-config", "restart-app", str(self.app), "--ignore-app-not-running"], instance.calls)
        docker = [call for call in instance.calls if call[0] == "docker"]
        self.assertEqual(1, len(docker))
        self.assertIn("pg_dump", " ".join(docker[0]))
        self.assertTrue(pathlib.Path(receipt["database_backup"]).exists())
        self.assertNotIn("customer-private-key", json.dumps(receipt))

    def test_backup_failure_keeps_previous_source_and_restores_worker(self):
        instance = self.instance()
        instance.fail = lambda args: args[0] == "docker"
        with self.assertRaises(subprocess.CalledProcessError):
            instance.execute()
        self.assertEqual(self.previous, git(self.app, "rev-parse", "HEAD"))
        self.assertFalse(instance.migration_started)
        self.assertTrue(instance.receipt["code_restored"])
        self.assertIn(["systemctl", "restart", "customer-sidekiq"], instance.calls)

    def test_native_migration_failure_requires_explicit_schema_compatibility_to_restore(self):
        instance = self.instance()
        instance.fail = lambda args: "db:migrate" in args
        with self.assertRaises(subprocess.CalledProcessError):
            instance.execute()
        self.assertEqual(self.desired, git(self.app, "rev-parse", "HEAD"))
        self.assertTrue(instance.receipt["migration_started"])
        self.assertNotIn("code_restored", instance.receipt)
        self.assertFalse(any("pg_restore" in args for args in instance.calls))

    def test_wrong_website_domain_never_reports_a_successful_native_release(self):
        instance = self.instance()
        instance.fail = lambda args: "lightek:site_binding:verify" in args
        with self.assertRaises(subprocess.CalledProcessError):
            instance.execute()
        self.assertEqual("failed", instance.receipt["status"])
        self.assertFalse(any("assets:precompile" in args for args in instance.calls))

    def test_compatible_native_migration_failure_restores_previous_checkout(self):
        instance = self.instance()
        instance.config["backward_compatible"] = True
        instance.fail = lambda args: "db:migrate" in args
        with self.assertRaises(subprocess.CalledProcessError):
            instance.execute()
        self.assertEqual(self.previous, git(self.app, "rev-parse", "HEAD"))
        self.assertTrue(instance.receipt["code_restored"])

    def test_native_retry_skips_migrations_only_when_running_passenger_revision_matches(self):
        instance = self.instance()
        instance.execute()
        instance.calls.clear()
        receipt = instance.execute()
        self.assertTrue(receipt["already_current"])
        self.assertFalse(any("db:migrate" in args for args in instance.calls))

    def test_scoped_knowledge_bundle_uses_the_existing_native_update_and_verified_receipt(self):
        instance = self.instance()
        instance.config["nevaeh_lessons"] = {"version": 1, "lessons": [{"key": "controlled-lesson"}], "sha256": "a" * 64}
        receipt = instance.execute()
        self.assertEqual("a" * 64, receipt["knowledge_bundle_sha256"])
        self.assertEqual(instance.config["nevaeh_lessons"], instance.lesson_input)
        instance.calls.clear()
        receipt = instance.execute()
        self.assertTrue(receipt["already_current"])
        self.assertEqual("a" * 64, receipt["knowledge_bundle_sha256"])
        self.assertFalse(any("db:migrate" in args for args in instance.calls))

    def test_failed_knowledge_import_cannot_report_successful_release(self):
        instance = self.instance()
        instance.config["nevaeh_lessons"] = {"version": 1, "lessons": [], "sha256": "b" * 64}
        instance.fail = lambda args: args[-1] == "script/nevaeh_apply_lesson_bundle.rb"
        with self.assertRaises(subprocess.CalledProcessError):
            instance.execute()
        self.assertEqual("failed", instance.receipt["status"])
        self.assertNotIn("knowledge_bundle_sha256", instance.receipt)

    def test_dirty_customer_checkout_is_preserved_and_refused(self):
        (self.app / "feature.rb").write_text("# uncommitted custom work\n")
        with self.assertRaisesRegex(ValueError, "local changes"):
            self.instance().execute()
        self.assertEqual("# uncommitted custom work\n", (self.app / "feature.rb").read_text())

    def test_new_checkout_is_not_enough_when_old_passenger_process_is_still_running(self):
        instance = self.instance()
        git(self.app, "fetch", "origin", self.desired)
        git(self.app, "checkout", "--detach", self.desired)
        with self.assertRaisesRegex(ValueError, "Running service revision"):
            instance.verify(self.desired)

    def test_repository_and_unexpected_previous_revision_are_refused(self):
        instance = self.instance()
        instance.config["repository"] = "https://example.test/account/someone-else.git"
        with self.assertRaisesRegex(ValueError, "identity"):
            instance.execute()
        instance = self.instance()
        instance.config["expected_previous_sha"] = "f" * 40
        with self.assertRaisesRegex(ValueError, "changed since"):
            instance.execute()
        self.assertEqual(self.previous, git(self.app, "rev-parse", "HEAD"))

    def test_nginx_cdn_validates_actual_included_configuration_before_reload(self):
        instance = self.instance("cdn_nginx")
        cache = self.app / "cache-object"
        cache.write_text("retained cached media")
        result = instance.execute()
        self.assertEqual("cdn_nginx", result["adapter"])
        self.assertEqual("retained cached media", cache.read_text())
        self.assertIn(["nginx", "-T"], instance.calls)
        self.assertIn(["systemctl", "reload", "nginx"], instance.calls)
        self.assertFalse(any(call[0] in ("docker", "bundle", "passenger-config") for call in instance.calls))

    def test_invalid_nginx_configuration_rolls_back_before_reloading_new_config(self):
        instance = self.instance("cdn_nginx")
        instance.fail = lambda args: args == ["nginx", "-T"] and git(self.app, "rev-parse", "HEAD") == self.desired
        with self.assertRaises(subprocess.CalledProcessError):
            instance.execute()
        self.assertEqual(self.previous, git(self.app, "rev-parse", "HEAD"))
        self.assertTrue(instance.receipt["code_restored"])

    def test_generic_service_runs_its_build_and_running_revision_verification_hooks(self):
        instance = self.instance("systemd_service")
        result = instance.execute()
        self.assertEqual("succeeded", result["status"])
        self.assertIn([str(self.app / "bin/build-service")], instance.calls)
        self.assertIn(["systemctl", "restart", "realtime"], instance.calls)
        self.assertFalse(any(args[0] == "docker" for args in instance.calls))

    def test_compose_worker_profile_only_controls_explicit_worker_not_rails_web(self):
        instance = self.instance(worker_mode="compose", worker_service="worker")
        instance.execute()
        controls = [args for args in instance.calls if args[0] == "docker"]
        self.assertTrue(any(args[-2:] == ["stop", "worker"] for args in controls))
        self.assertTrue(any(args[-2:] == ["start", "worker"] for args in controls))
        self.assertFalse(any("web" in args or "up" in args or "pull" in args for args in controls))

    def test_unverified_specialized_service_and_malformed_profiles_are_refused(self):
        for profile in ({"app_root": "/tmp/../etc"}, {"health_url": "https://attacker.example.com/up"},
                        {"worker_service": "sidekiq; reboot"}, {"env_file": "relative.env"}):
            config = dict(self.config, deployment=dict(self.config["deployment"], **profile))
            with self.subTest(profile=profile), self.assertRaises(ValueError):
                native.validate(config)
        config = dict(self.config, adapter="systemd_service", deployment=dict(app_root=str(self.app), app_user="lightek",
            health_url="https://customer.example.com/up", service_name="worker"))
        with self.assertRaisesRegex(ValueError, "revision"):
            native.validate(config)

    def test_native_user_commands_pass_profile_paths_as_arguments(self):
        instance = native.NativeUpdater(self.config, self.base / "state")
        captured = []
        with patch.object(instance, "command", side_effect=lambda args, **kwargs: captured.append(args)):
            instance.as_user(["bundle", "exec", "rails", "db:migrate"])
        command = captured[0]
        self.assertIn("BUNDLE_FROZEN=true", command)
        self.assertEqual([str(self.app), str(self.env), "bundle", "exec", "rails", "db:migrate"], command[-6:])

    def test_revision_probe_routes_to_this_instance_with_original_tls_hostname(self):
        instance = native.NativeUpdater(self.config, self.base / "state")
        body = json.dumps({"source_sha": self.desired}).encode()
        tls_socket = MagicMock()
        tls_socket.makefile.return_value = io.BytesIO(b"HTTP/1.1 200 OK\r\nContent-Length: " + str(len(body)).encode() + b"\r\n\r\n" + body)
        context = MagicMock()
        context.wrap_socket.return_value = tls_socket
        raw = MagicMock()
        with patch.object(native.socket, "create_connection", return_value=raw) as connect, \
             patch.object(native.ssl, "create_default_context", return_value=context):
            result = instance.request(self.config["deployment"]["revision_url"])
        self.assertEqual(self.desired, json.loads(result)["source_sha"])
        self.assertEqual(("127.0.0.1", 443), connect.call_args.args[0])
        context.wrap_socket.assert_called_once_with(raw, server_hostname="customer.example.com")
        sent = b"".join(call.args[0] for call in tls_socket.sendall.call_args_list)
        self.assertIn(b"Host: customer.example.com", sent)


if __name__ == "__main__":
    unittest.main()
