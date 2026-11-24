import unittest
from unittest import mock
import lightek_device_agent as agent


class EndpointChecksTest(unittest.TestCase):
    def test_inventory_is_read_only(self):
        result = agent.read_only_check("refresh_inventory")
        self.assertEqual(result["status"], "ok")

    def test_unsupported_actions_are_rejected(self):
        for code in ("execute_shell", "install_patch", "restore_backup", None):
            self.assertIsNone(agent.read_only_check(code))

    def test_unknown_platform_does_not_claim_verified_protection_or_backups(self):
        with mock.patch.object(agent.sys, "platform", "unsupported"):
            for code in ("check_patch_status", "check_backup_status", "check_endpoint_protection"):
                self.assertEqual(agent.read_only_check(code)["status"], "unavailable")

    def test_linux_patch_inventory_does_not_install(self):
        with (mock.patch.object(agent.sys, "platform", "linux"),
              mock.patch.object(agent.shutil, "which", return_value="/usr/bin/apt"),
              mock.patch.object(agent, "_probe", return_value=(0, "Listing...\\npackage [upgradable from: 1]")) as probe):
            result = agent.read_only_check("check_patch_status")
        self.assertEqual(result["status"], "warning")
        probe.assert_called_once_with(["apt", "list", "--upgradable"])

    def test_probe_never_uses_shell(self):
        completed = mock.Mock(returncode=0, stdout="ok", stderr="")
        with mock.patch.object(agent.subprocess, "run", return_value=completed) as run:
            self.assertEqual(agent._probe(["apt", "list", "--upgradable"]), (0, "ok"))
        self.assertFalse(run.call_args.kwargs["shell"])
        self.assertTrue(run.call_args.kwargs["timeout"] <= 12)

    def test_windows_defender_status_does_not_claim_remediation(self):
        with (mock.patch.object(agent.sys, "platform", "win32"),
              mock.patch.object(agent, "_probe", return_value=(0, "False"))):
            result = agent.read_only_check("check_endpoint_protection")
        self.assertEqual(result["status"], "warning")
        self.assertIn("false", result["observation"])

    def test_mac_backup_is_not_claimed_restorable(self):
        with (mock.patch.object(agent.sys, "platform", "darwin"),
              mock.patch.object(agent.shutil, "which", return_value="/usr/bin/tmutil"),
              mock.patch.object(agent, "_probe", return_value=(0, "/Volumes/Backup/Latest"))):
            result = agent.read_only_check("check_backup_status")
        self.assertEqual(result["status"], "warning")
        self.assertIn("not verified", result["observation"])

    def test_heartbeat_actions_are_bounded(self):
        calls = []
        def fake_post(payload):
            calls.append(payload)
            if payload["method_type"] == "device_heartbeat":
                return {"ok": True, "maintenance_actions": [
                    {"id": 1, "code": "refresh_inventory", "nonce": "a" * 48},
                    {"id": 2, "code": "execute_shell", "nonce": "b" * 48}]}
            return {"ok": True}
        with mock.patch.dict(agent.os.environ, {"LIGHTEK_DEVICE_IDENTIFIER": "test"}), \
             mock.patch.object(agent, "collect", return_value={"disk_percent": 50}), \
             mock.patch.object(agent, "post", side_effect=fake_post):
            agent.report()
        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[1]["method_type"], "device_maintenance_report")
        self.assertEqual(calls[1]["action_id"], 1)


if __name__ == "__main__":
    unittest.main()
