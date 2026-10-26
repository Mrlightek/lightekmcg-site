import importlib.util
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("mail_server", ROOT / "lib/scripts/lightek_mail_server.py")
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)


class MailServerPlanTest(unittest.TestCase):
    def test_private_bootstrap_blocks_senders_and_internet_delivery(self):
        configs = server.configuration("mail.example.test")
        postfix = configs["postfix/main.cf"]
        self.assertIn("inet_interfaces = loopback-only", postfix)
        self.assertIn("defer_transports = smtp", postfix)
        self.assertIn("reject_unauth_destination", postfix)
        self.assertIn("milter_default_action = tempfail", postfix)
        self.assertIn("authorized_submit_users =\n", postfix)
        self.assertNotIn(" OK", configs["postfix/lightek_senders"])
        self.assertIn("127.0.0.1:11333", configs["rspamd/local.d/worker-normal.inc"])
        self.assertIn("enabled = false", configs["rspamd/local.d/worker-controller.inc"])
        self.assertIn("127.0.0.1:16379", configs["rspamd/local.d/redis.conf"])
        self.assertIn('selector = "from(\'smtp\').lower"', configs["rspamd/local.d/ratelimit.conf"])

    def test_invalid_hostnames_cannot_inject_configuration_or_dkim_paths(self):
        for value in ("mail.test\ninet_interfaces = all", "../../mail.test", "mail.test;bad", "mail..test"):
            with self.assertRaises(ValueError):
                server.configuration(value)

    def test_plan_writes_only_to_requested_directory_and_refuses_target_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            server.write_plan(root / "plan", "mail.example.test")
            self.assertTrue((root / "plan/postfix/main.cf").is_file())
            target = root / "preserve.txt"
            target.write_text("preserved")
            path = root / "plan/postfix/main.cf"
            path.unlink()
            path.symlink_to(target)
            with self.assertRaises(ValueError):
                server.write_plan(root / "plan", "mail.example.test")
            self.assertEqual("preserved", target.read_text())


if __name__ == "__main__":
    unittest.main()
