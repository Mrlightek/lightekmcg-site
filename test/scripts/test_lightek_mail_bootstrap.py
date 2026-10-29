#!/usr/bin/env python3
"""Executable, unprivileged mail bootstrap contract tests.

Run: python3 -m unittest discover -s test/scripts -p 'test_lightek_mail_bootstrap.py'
"""
import importlib.util
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[2] / "lib/scripts/lightek_mail_server.py"
spec = importlib.util.spec_from_file_location("lightek_mail_server", SCRIPT)
mail = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mail)


class MailBootstrapContractTest(unittest.TestCase):
    def test_valid_hostname(self):
        self.assertEqual(mail.hostname("mail.customer.example"), "mail.customer.example")

    def test_invalid_hostname_is_rejected(self):
        for value in ("MAIL.example.com", "localhost", "mail..example", "mail.example;rm -rf /"):
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    mail.hostname(value)

    def test_plan_writes_private_services_only(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            mail.write_plan(root, "mail.customer.example")
            main = (root / "postfix/main.cf").read_text()
            dovecot = (root / "dovecot/conf.d/99-lightek.conf").read_text()
            self.assertIn("inet_interfaces = loopback-only", main)
            self.assertIn("defer_transports = smtp", main)
            self.assertIn("listen = 127.0.0.1", dovecot)
            self.assertIn("ssl = required", dovecot)
            self.assertFalse((root / "postfix/master.cf").exists())

    def test_plan_refuses_symlink_target(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            victim = root / "victim"
            victim.write_text("unchanged")
            target = root / "postfix/main.cf"
            target.parent.mkdir()
            target.symlink_to(victim)
            with self.assertRaises(ValueError):
                mail.write_plan(root, "mail.customer.example")
            self.assertEqual(victim.read_text(), "unchanged")


if __name__ == "__main__":
    unittest.main()
