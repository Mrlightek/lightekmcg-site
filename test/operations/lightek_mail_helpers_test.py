import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import pwd
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

ROOT = Path(__file__).resolve().parents[2]


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "lib/scripts" / (name + ".py"))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


class MailHelpersTest(unittest.TestCase):
    def test_prepare_is_private_idempotent_and_preserves_existing_environment(self):
        prepare = module("prepare_lightek_mail_ingress")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            env, config = root / "production.env", root / "ingress.json"
            env.write_text("EXISTING_SETTING=preserved\n")
            args = ["prepare", "--env-file", str(env), "--app-user", pwd.getpwuid(os.getuid()).pw_name,
                    "--config-file", str(config), "--backup-directory", str(root / "backups")]
            with patch("sys.argv", args), patch.object(prepare.os, "geteuid", return_value=0), patch.object(prepare.os, "chown"), contextlib.redirect_stdout(io.StringIO()):
                prepare.main()
                first = env.read_text()
                prepare.main()
            self.assertEqual(first, env.read_text())
            token = json.loads(config.read_text())["token"]
            self.assertEqual(64, len(token))
            self.assertIn("EXISTING_SETTING=preserved", first)
            self.assertIn("LIGHTEK_MAIL_INGRESS_TOKEN=" + token, first)
            feedback = next(line.split("=", 1)[1] for line in first.splitlines() if line.startswith("LIGHTEK_MAIL_FEEDBACK_TOKEN="))
            self.assertEqual(64, len(feedback))
            self.assertNotEqual(token, feedback)
            self.assertEqual(0o600, config.stat().st_mode & 0o777)
            backups = list((root / "backups").glob("*/production.env"))
            self.assertEqual(1, len(backups))
            self.assertEqual("EXISTING_SETTING=preserved\n", backups[0].read_text())
            self.assertEqual(0o600, backups[0].stat().st_mode & 0o777)

    def test_ingress_preserves_raw_mime_and_envelope_and_refuses_redirects(self):
        ingress = module("lightek_mail_ingress")
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "config.json"
            config.write_text(json.dumps({"url": "https://mail.example.test/api/lightek-mail/inbound", "token": "fixture-only"}))
            requests = []
            class Response:
                status = 202
                def __enter__(self): return self
                def __exit__(self, *args): pass
            class Opener:
                def open(self, request, **kwargs):
                    requests.append(request)
                    return Response()
            with patch("sys.argv", ["ingress", "--recipient", "care@example.test", "--config", str(config)]), patch("sys.stdin", io.TextIOWrapper(io.BytesIO(b"From: sender@example.test\r\n\r\nRaw MIME"))), patch.object(ingress.urllib.request, "build_opener", return_value=Opener()) as build:
                self.assertEqual(0, ingress.main())
                self.assertIsNone(build.call_args.args[0].redirect_request(None, None, None, None))
            self.assertEqual(b"From: sender@example.test\r\n\r\nRaw MIME", requests[0].data)
            self.assertEqual('["care@example.test"]', requests[0].get_header("X-lightek-mail-recipients"))

    def test_ingress_retains_queue_on_network_failure_without_echoing_error_details(self):
        ingress = module("lightek_mail_ingress")
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "config.json"
            config.write_text(json.dumps({"url": "https://mail.example.test/api/lightek-mail/inbound", "token": "fixture"}))
            class Opener:
                def open(self, *args, **kwargs): raise urllib.error.URLError("private fixture failure")
            with patch("sys.argv", ["ingress", "--recipient", "care@example.test", "--config", str(config)]), patch("sys.stdin", io.TextIOWrapper(io.BytesIO(b"raw"))), patch.object(ingress.urllib.request, "build_opener", return_value=Opener()), contextlib.redirect_stderr(io.StringIO()) as error:
                self.assertEqual(75, ingress.main())
            self.assertNotIn("private fixture failure", error.getvalue())


if __name__ == "__main__":
    unittest.main()
