import fcntl
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
REVISION = "a" * 40


class PrimaryWorkerWatchdogTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.state = self.root / "state"
        self.app = self.root / "checkout"
        self.bin = self.root / "bin"
        for path in (self.state, self.app, self.bin):
            path.mkdir()
        self.lock = self.root / "fleet" / hashlib.sha256(str(self.app).encode()).hexdigest()[:24] / "update.lock"
        self.lock.parent.mkdir(parents=True)
        self.marker = self.state / "verified-release"
        self.marker.write_text(REVISION + "\n")
        source = (ROOT / "lib/scripts/gatekeeper/primary_worker_watchdog.sh").read_text()
        self.script = self.root / "watchdog.sh"
        self.script.write_text(source.replace("/var/lib/lightek/primary-worker-watchdog", str(self.state))
                               .replace("/var/www/lightekmcg-site", str(self.app))
                               .replace("/var/lib/lightek/fleet", str(self.root / "fleet")))
        self.starts = self.root / "starts"
        self.env = {**os.environ, "PATH": f"{self.bin}:{os.environ['PATH']}", "FIXTURE_SHA": REVISION,
                    "FIXTURE_SERVED": REVISION, "FIXTURE_STATE": "failed", "STARTS": str(self.starts)}
        self.mock("git", 'echo "$FIXTURE_SHA"')
        self.mock("curl", 'printf \'{"component":"lightek_app","source_sha":"%s"}\' "$FIXTURE_SERVED"')
        self.mock("runuser", '[[ "$1" == -u && "$2" == lightek && "${FIXTURE_QUEUE_READY:-1}" == 1 ]]')
        self.mock("systemctl", """
case "$1" in
  is-active) [[ "$3" == apache2.service || "$FIXTURE_STATE" == active || ( -f "$STARTS" && "${FIXTURE_FAIL_START:-0}" == 0 ) ]] ;;
  is-failed) [[ "$FIXTURE_STATE" == failed ]] ;;
  start) echo "$2" >> "$STARTS"; [[ "${FIXTURE_FAIL_START:-0}" == 0 ]] ;;
  show) echo 123 ;;
  *) exit 1 ;;
esac
""")

    def mock(self, name, code):
        file = self.bin / name
        file.write_text("#!/bin/bash\n" + code + "\n")
        file.chmod(0o755)

    def run_watchdog(self, **values):
        return subprocess.run(["bash", str(self.script)], env={**self.env, **values}, capture_output=True, text=True)

    def test_recovers_only_the_failed_primary_worker_under_the_verified_release(self):
        result = self.run_watchdog()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("GATEKEEPER_PRIMARY_WORKER_RECOVERED", result.stdout)
        self.assertEqual(self.starts.read_text(), "lightekmcg-site-sidekiq.service\n")
        self.assertTrue((self.state / "attempted-release").exists())
        self.run_watchdog(FIXTURE_STATE="active")
        self.assertFalse((self.state / "attempted-release").exists())

    def test_failed_restart_consumes_the_outage_attempt(self):
        self.assertNotEqual(self.run_watchdog(FIXTURE_FAIL_START="1").returncode, 0)
        self.assertEqual(self.run_watchdog(FIXTURE_FAIL_START="1").returncode, 0)
        self.assertEqual(len(self.starts.read_text().splitlines()), 1)

    def test_does_not_report_recovery_before_the_queue_consumer_registers(self):
        result = self.run_watchdog(FIXTURE_QUEUE_READY="0")
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("GATEKEEPER_PRIMARY_WORKER_RECOVERED", result.stdout)

    def test_refuses_unverified_web_checkout_and_intentional_stops(self):
        for env in ({"FIXTURE_SERVED": "b" * 40}, {"FIXTURE_SHA": "b" * 40}, {"FIXTURE_STATE": "inactive"}):
            self.run_watchdog(**env)
            self.assertFalse(self.starts.exists())
            self.assertFalse((self.state / "attempted-release").exists())

    def test_does_not_recover_during_a_deployment(self):
        with self.lock.open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            self.assertEqual(self.run_watchdog().returncode, 0)
        self.assertFalse(self.starts.exists())


if __name__ == "__main__":
    unittest.main()
