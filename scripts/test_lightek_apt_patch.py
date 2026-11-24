import os
import subprocess
import sys
import unittest
from unittest.mock import Mock, patch

if sys.platform == "linux":
    import lightek_apt_patch as broker


@unittest.skipUnless(sys.platform == "linux", "Debian APT broker")
class AptPatchBrokerTest(unittest.TestCase):
    def setUp(self):
        self.target = "test-package=2.0"
        self.policy = Mock()
        self.policy.parent.stat.return_value = Mock(st_uid=0, st_mode=0o40755)
        self.policy.stat.return_value = Mock(st_uid=0, st_mode=0o100644, st_size=32)
        self.policy.read_text.return_value = self.target + "\n"

    def test_reads_dpkg_status_with_its_native_fixed_width_padding(self):
        with patch.object(broker, "run", return_value=Mock(stdout="ii  1:2.0-2")):
            self.assertEqual(broker.installed_version("test-package"), "1:2.0-2")
        with patch.object(broker, "run", return_value=Mock(stdout="iU  1:2.0-2")):
            with self.assertRaises(ValueError):
                broker.installed_version("test-package")

    def test_refuses_targets_outside_local_policy(self):
        with (patch.object(broker, "POLICY", self.policy), patch.object(os, "geteuid", return_value=0),
              patch.object(broker, "run") as run):
            result = broker.deployment("test-package=2.1")
        self.assertEqual(result, {"status": "unavailable"})
        run.assert_not_called()

    def test_refuses_package_manager_changes_outside_the_approved_package(self):
        with (patch.object(broker, "POLICY", self.policy), patch.object(os, "geteuid", return_value=0),
              patch.object(broker, "installed_version", return_value="1.0"),
              patch.object(broker, "run") as run):
            run.side_effect = [Mock(stdout=""), Mock(stdout="Inst test-package\nInst dependency\n")]
            result = broker.deployment(self.target)
        self.assertEqual(result, {"status": "unavailable"})
        self.assertEqual(run.call_count, 2)

    def test_downloads_exact_package_and_rechecks_installed_version(self):
        with (patch.object(broker, "POLICY", self.policy), patch.object(os, "geteuid", return_value=0),
              patch.object(broker, "installed_version", side_effect=["1.0", "2.0"]) as installed,
              patch.object(broker, "run") as run):
            def command(*args, **kwargs):
                if "download" in args:
                    (broker.Path(kwargs["cwd"]) / "test-package.deb").touch()
                outputs = {"-s": "Inst test-package\nConf test-package\n", "Package": "test-package", "Version": "2.0"}
                return subprocess.CompletedProcess(args, 0, outputs.get(args[-1], outputs.get(args[1], "")), "")
            run.side_effect = command
            result = broker.deployment(self.target)
        self.assertEqual(result, {"status": "installed", "target": self.target})
        self.assertEqual(installed.call_count, 2)
        self.assertEqual(sum("--install" in call.args for call in run.call_args_list), 1)
