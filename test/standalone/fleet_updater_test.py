import importlib.util
import json
import pathlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("updater", ROOT / "lib/scripts/gatekeeper/update_installation.py")
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)
spec = importlib.util.spec_from_file_location("builder", ROOT / "script/lightek/build_fleet_release.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class FleetUpdaterTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = pathlib.Path(self.temporary.name)
        self.config = dict(domain="customer.example.com", source_sha="a" * 40,
            image="ghcr.io/example/customer@sha256:" + "b" * 64,
            target_id=7, attempt=1, backward_compatible=False)
        self.site = self.base / self.config["domain"]
        self.site.mkdir()
        self.original = ('POSTGRES_PASSWORD="customer-db-secret"\nSECRET_KEY_BASE="customer-key"\n'
            'LIGHTEK_DEPLOYED_SITE_HOST="customer.example.com"\nPROJECT="lt_1234567890abcdef"\n'
            'APP_PORT="18081"\nLIGHTEK_RELEASE="previous"\nCUSTOM_FEATURE="keep-me"\n')
        (self.site / ".env").write_text(self.original)
        (self.site / "managed.json").write_text(json.dumps(dict(domain=self.config["domain"], project="lt_1234567890abcdef")))
        (self.site / "current-release").write_text("previous\n")
        (self.site / "compose.yml").write_text("services: {}\n")
        self.calls = []
        self.fail_on = None

    def process(self, args, **kwargs):
        self.calls.append((args, kwargs))
        if self.fail_on and self.fail_on(args):
            raise subprocess.CalledProcessError(1, args)
        if "pg_dump" in " ".join(args):
            kwargs["stdout"].write(b"-- consistent customer database\n")
        return subprocess.CompletedProcess(args, 0)

    def execute(self, **changes):
        instance = updater.Updater(dict(self.config, **changes), base=self.base)
        with patch.object(updater.subprocess, "run", side_effect=self.process), \
             patch.object(updater.subprocess, "check_output", side_effect=self.inspection), \
             patch.object(updater.Updater, "healthy", return_value={"ok": True}):
            return instance.execute()

    def inspection(self, args, **kwargs):
        if "ps" in args:
            return "container-id\n"
        if "inspect" in args and "image" not in args:
            return self.config["image"] + " true\n"
        return self.config["source_sha"] + "\n"

    def test_success_preserves_customer_secrets_storage_and_compose_configuration(self):
        receipt = self.execute()
        env = updater.environment((self.site / ".env").read_text())
        self.assertEqual('"customer-db-secret"', env["POSTGRES_PASSWORD"])
        self.assertEqual('"customer-key"', env["SECRET_KEY_BASE"])
        self.assertEqual('"keep-me"', env["CUSTOM_FEATURE"])
        self.assertEqual('"18081"', env["APP_PORT"])
        self.assertEqual('"' + self.config["source_sha"] + '"', env["LIGHTEK_RELEASE"])
        self.assertEqual("services: {}\n", (self.site / "compose.yml").read_text())
        self.assertEqual("succeeded", receipt["status"])
        self.assertTrue(pathlib.Path(receipt["database_backup"]).exists())
        self.assertNotIn("customer-db-secret", json.dumps(receipt))
        commands = [" ".join(command) for command, _ in self.calls]
        self.assertTrue(any("stop web worker" in command for command in commands))
        self.assertTrue(any("db:migrate" in command for command in commands))
        self.assertFalse(any("bootstrap" in command or "volume rm" in command or "down" in command for command in commands))
        self.assertLess(next(i for i, c in enumerate(commands) if "pg_dump" in c), next(i for i, c in enumerate(commands) if "db:migrate" in c))

    def test_retry_of_verified_current_version_does_not_migrate_or_restart(self):
        self.execute()
        self.calls.clear()
        receipt = self.execute(attempt=2)
        self.assertTrue(receipt["already_current"])
        self.assertEqual([], self.calls)

    def test_backup_failure_restores_previous_code_before_any_migration(self):
        self.fail_on = lambda args: "pg_dump" in " ".join(args)
        with self.assertRaises(subprocess.CalledProcessError):
            self.execute()
        self.assertEqual(self.original, (self.site / ".env").read_text())
        self.assertFalse((self.site / "fleet-image.json").exists())
        self.assertFalse(any("db:migrate" in args for args, _ in self.calls))
        receipt = json.loads((self.site / "backups/fleet-7-1.json").read_text())
        self.assertTrue(receipt["code_restored"])
        self.assertFalse(receipt["migration_started"])

    def test_incompatible_migration_failure_does_not_restore_code_or_database(self):
        self.fail_on = lambda args: "db:migrate" in args
        with self.assertRaises(subprocess.CalledProcessError):
            self.execute()
        self.assertNotEqual(self.original, (self.site / ".env").read_text())
        receipt = json.loads((self.site / "backups/fleet-7-1.json").read_text())
        self.assertTrue(receipt["migration_started"])
        self.assertNotIn("code_restored", receipt)
        self.assertFalse(any("psql" in args or "pg_restore" in args for args, _ in self.calls))

    def test_compatible_migration_failure_restores_previous_image_settings(self):
        previous = {"services": {"web": {"image": "old-image"}, "worker": {"image": "old-image"}}}
        (self.site / "fleet-image.json").write_text(json.dumps(previous))
        self.fail_on = lambda args: "db:migrate" in args
        with self.assertRaises(subprocess.CalledProcessError):
            self.execute(backward_compatible=True)
        self.assertEqual(self.original, (self.site / ".env").read_text())
        self.assertEqual(previous, json.loads((self.site / "fleet-image.json").read_text()))
        receipt = json.loads((self.site / "backups/fleet-7-1.json").read_text())
        self.assertTrue(receipt["code_restored"])

    def test_image_pull_failure_leaves_running_installation_untouched(self):
        self.fail_on = lambda args: "pull" in args
        with self.assertRaises(subprocess.CalledProcessError):
            self.execute()
        self.assertEqual(self.original, (self.site / ".env").read_text())
        self.assertFalse(any("stop" in args for args, _ in self.calls))

    def test_digest_and_source_label_must_match_before_stopping_customer(self):
        instance = updater.Updater(self.config, base=self.base)
        with patch.object(updater.subprocess, "run", side_effect=self.process), \
             patch.object(updater.subprocess, "check_output", return_value="wrong-revision\n"):
            with self.assertRaisesRegex(ValueError, "provenance"):
                instance.execute()
        self.assertEqual(self.original, (self.site / ".env").read_text())
        self.assertFalse(any("stop" in args for args, _ in self.calls))

    def test_hostname_ownership_mismatch_prevents_all_mutations(self):
        (self.site / "managed.json").write_text(json.dumps(dict(domain="someone-else.example.com", project="lt_1234567890abcdef")))
        with self.assertRaisesRegex(ValueError, "ownership"):
            self.execute()
        self.assertEqual([], self.calls)
        self.assertEqual(self.original, (self.site / ".env").read_text())

    def test_registry_password_is_only_sent_on_stdin_and_not_saved(self):
        self.execute(registry={"username": "registry-reader", "password": "private-registry-token"})
        command, kwargs = next((args, kwargs) for args, kwargs in self.calls if "login" in args)
        self.assertNotIn("private-registry-token", " ".join(command))
        self.assertEqual(b"private-registry-token", kwargs["input"])
        for path in self.site.rglob("*"):
            if path.is_file():
                self.assertNotIn("private-registry-token", path.read_text())

    def test_invalid_targets_images_and_attempts_are_rejected(self):
        for change in ({"domain": "../other"}, {"domain": "x; touch /tmp/owned"}, {"image": "ghcr.io/customer:latest"},
                       {"image": "ghcr.io/customer@sha256:bad"}, {"source_sha": "main"}, {"target_id": 0},
                       {"attempt": True}, {"backward_compatible": "true"}):
            with self.subTest(change=change), self.assertRaises((ValueError, KeyError)):
                updater.validate(dict(self.config, **change))

    def test_runtime_verification_checks_worker_and_web_digest(self):
        instance = updater.Updater(self.config, base=self.base)
        instance.project = "lt_1234567890abcdef"
        def wrong_image(args, **kwargs):
            return "container-id\n" if "ps" in args else "old-image true\n"
        with patch.object(updater.subprocess, "check_output", side_effect=wrong_image):
            with self.assertRaisesRegex(ValueError, "Running image"):
                instance.verify_runtime(self.config["source_sha"])

    def test_built_context_uses_delivery_adapters_and_vendors_dependencies_without_secrets(self):
        source = self.base / "source"
        (source / "script/lightek").mkdir(parents=True)
        (source / "script/lightek/website_deploy.sh").write_text((ROOT / "script/lightek/website_deploy.sh").read_text())
        (source / "config").mkdir()
        (source / "config/routes.rb").write_text("Rails.application.routes.draw do\nend\n")
        (source / "config/application.rb").write_text('require_relative "boot"\n')
        (source / "config/master.key").write_text("do-not-package")
        (source / ".env").write_text("do-not-package")
        (source / "bin").mkdir()
        private = self.base / "private-gem"
        private.mkdir()
        (private / "lib").mkdir()
        (private / "lib/private.rb").write_text("module Private; end\n")
        (private / ".git").mkdir()
        (private / ".git/config").write_text("https://private-git-token@example.com")
        def commands(args, **kwargs):
            if args[:3] == ["bundle", "exec", "ruby"]:
                pathlib.Path(args[-1]).write_text(json.dumps(dict(ruby="3.3.6", bundler="2.6.3", gems=[
                    dict(name="private", version="1.0.0", path=str(private), gemspec="Gem::Specification.new {}", autorequire=None)])))
            return subprocess.CompletedProcess(args, 0)
        output = self.base / "image-context"
        with patch.object(builder.subprocess, "run", side_effect=commands), \
             patch.object(builder.subprocess, "check_output", return_value="a" * 40):
            builder.build(source, output)
        self.assertTrue((output / "app/controllers/lightek_website_delivery_controller.rb").exists())
        self.assertTrue((output / "vendor/lightek_sources/private/lib/private.rb").exists())
        self.assertIn('org.opencontainers.image.revision="' + "a" * 40 + '"', (output / "Dockerfile").read_text())
        self.assertIn("/__lightek/website-health", (output / "config/routes.rb").read_text())
        for path in output.rglob("*"):
            if path.is_file():
                self.assertNotIn("do-not-package", path.read_text())
                self.assertNotIn("private-git-token", path.read_text())

    def test_builder_reuses_installer_adapters_and_excludes_private_files(self):
        helpers = builder.installer_helpers(ROOT)
        ignore = helpers["ignored"]("config", ["master.key", "credentials.yml.enc", "routes.rb", ".env", "token.pem"])
        self.assertIn("master.key", ignore)
        self.assertIn("credentials.yml.enc", ignore)
        self.assertIn(".env", ignore)
        self.assertIn("token.pem", ignore)
        self.assertNotIn("routes.rb", ignore)
        self.assertIn("Dockerfile", helpers["PAYLOAD"])


if __name__ == "__main__":
    unittest.main()
