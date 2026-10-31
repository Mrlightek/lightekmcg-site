"""Exercise the actual deploy restart phase against a transient CLI failure."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PassengerRestartTest(unittest.TestCase):
    def run_restart_phase(self, cli_status, blocked_tmp=False):
        source = (ROOT / 'lib/scripts/gatekeeper/deploy_project.sh').read_text()
        phase = source.split('echo "[7/8] Apache"', 1)[1].split('echo "[8/8] Health"', 1)[0]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            application = root / 'application'
            application.mkdir()
            commands = root / 'bin'
            commands.mkdir()
            cli = commands / 'passenger-config'
            cli.write_text('#!/bin/sh\nexit ' + str(cli_status) + '\n')
            cli.chmod(0o755)
            if blocked_tmp:
                (application / 'tmp').write_text('Cannot use a file as a directory')
            script = '''set -euo pipefail
apache2ctl() { return 0; }
systemctl() { return 0; }
run_as_app_user() { (cd "$APP_ROOT"; bash -e -c "$*"); }
''' + phase
            result = subprocess.run(['bash'], input=script, text=True, capture_output=True,
                                    env=dict(os.environ, APP_ROOT=str(application), APACHE_SERVICE='fixture', PATH=str(commands) + ':' + os.environ['PATH']))
            marker = application / 'tmp/restart.txt'
            return result.returncode, marker.is_file()

    def test_successful_control_command_requires_no_fallback_marker(self):
        self.assertEqual((0, False), self.run_restart_phase(0))

    def test_transient_cli_failure_requests_restart_and_allows_health_gate_to_run(self):
        self.assertEqual((0, True), self.run_restart_phase(1))

    def test_unwritable_restart_target_stops_deployment_instead_of_claiming_success(self):
        code, marker = self.run_restart_phase(1, blocked_tmp=True)
        self.assertNotEqual(0, code)
        self.assertFalse(marker)


if __name__ == '__main__':
    unittest.main()
