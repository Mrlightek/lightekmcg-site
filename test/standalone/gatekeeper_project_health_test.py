import fcntl
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
REVISION = "a" * 40


class GatekeeperProjectHealthTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.app = self.root / "app"
        self.app.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        # Redirect the production lock directory into the fixture. The verifier
        # still uses the real checkout hash and a real flock.
        source = (ROOT / "lib/scripts/gatekeeper/healthcheck_project.sh").read_text()
        self.script = self.root / "probe.sh"
        self.script.write_text(source.replace("/var/lib/lightek/fleet", str(self.root / "fleet")))
        self.worker_state = self.root / "worker_state"
        self.worker_state.write_text("failed")
        self.start_log = self.root / "starts"
        self.env = {
            **os.environ,
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "APP_ROOT": str(self.app),
            "APP_DOMAIN": "example.test",
            "APACHE_SERVICE": "apache2",
            "SIDEKIQ_SERVICE": "example-sidekiq",
            "EXPECTED_WORKER_RELEASE": REVISION,
            "FIXTURE_WORKER_STATE": str(self.worker_state),
            "FIXTURE_START_LOG": str(self.start_log),
            "FIXTURE_REVISION": REVISION,
            "FIXTURE_HTTP_STATUS": "200",
        }
        self.stub("git", 'printf "%s\n" "$FIXTURE_REVISION"')
        self.stub("curl", 'printf "%s" "$FIXTURE_HTTP_STATUS"')
        self.stub("passenger-status", 'printf "%s\n" "$APP_ROOT"')
        self.stub(
            "systemctl",
            """
case "$1" in
  is-active) [[ "$3" == apache2 ]] || [[ "$(cat "$FIXTURE_WORKER_STATE")" == active ]] ;;
  is-failed) [[ "$(cat "$FIXTURE_WORKER_STATE")" == failed ]] ;;
  start)
    printf "%s\n" "$2" >> "$FIXTURE_START_LOG"
    printf active > "$FIXTURE_WORKER_STATE"
    ;;
  *) exit 1 ;;
esac
""",
        )

    def stub(self, name, body):
        path = self.bin / name
        path.write_text(f"#!/usr/bin/env bash\n{body}\n")
        path.chmod(0o755)

    def probe(self, **overrides):
        return subprocess.run(
            ["bash", str(self.script)],
            env={**self.env, **overrides},
            capture_output=True,
            text=True,
            check=False,
        )

    def test_starts_only_the_failed_worker_and_reports_verified_recovery(self):
        result = self.probe()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("GATEKEEPER_WORKER_RECOVERED=1", result.stdout)
        self.assertEqual(self.start_log.read_text().splitlines(), ["example-sidekiq"])
        subsequent = self.probe()
        self.assertEqual(subsequent.returncode, 0)
        self.assertNotIn("GATEKEEPER_WORKER_RECOVERED=1", subsequent.stdout)
        self.assertEqual(self.start_log.read_text().splitlines(), ["example-sidekiq"])

    def test_skips_recovery_without_a_matching_verified_release_or_healthy_web(self):
        for overrides in [
            {"EXPECTED_WORKER_RELEASE": ""},
            {"FIXTURE_REVISION": "b" * 40},
            {"FIXTURE_HTTP_STATUS": "503"},
        ]:
            with self.subTest(overrides=overrides):
                result = self.probe(**overrides)
                self.assertEqual(result.returncode, 1)
                self.assertNotIn("GATEKEEPER_WORKER_RECOVERED=1", result.stdout)
                self.assertFalse(self.start_log.exists())

    def test_leaves_intentionally_stopped_workers_alone(self):
        self.worker_state.write_text("inactive")
        self.assertEqual(self.probe().returncode, 1)
        self.assertFalse(self.start_log.exists())

    def test_never_starts_workers_during_a_deployment(self):
        lock_key = hashlib.sha256(str(self.app.resolve()).encode()).hexdigest()[:24]
        lock_dir = self.root / "fleet" / lock_key
        lock_dir.mkdir(parents=True)
        with (lock_dir / "update.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assertEqual(self.probe().returncode, 1)
        self.assertFalse(self.start_log.exists())


if __name__ == "__main__":
    unittest.main()
