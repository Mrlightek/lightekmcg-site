import importlib.util
import json
import os
import pathlib
import pwd
import subprocess
import tempfile
import unittest
from unittest.mock import MagicMock, patch

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("hosted", ROOT / "lib/scripts/gatekeeper/create_hosted_site.py")
hosted = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hosted)


class SiteRuntime(hosted.HostedSite):
    def __init__(self, config, system_root):
        super().__init__(config, system_root)
        self.calls = []
        self.bootstrap_count = 0
        self.fail = lambda args: False

    def run(self, args, input=None, capture=False):
        self.calls.append((args, input))
        if self.fail(args):
            raise subprocess.CalledProcessError(1, args)
        if args[0] == "a2ensite":
            link = self.system_root / "etc/apache2/sites-enabled" / args[1]
            if not link.exists():
                link.symlink_to(self.system_root / "etc/apache2/sites-available" / args[1])
        if args[0] == "a2dissite":
            (self.system_root / "etc/apache2/sites-enabled" / args[1]).unlink(missing_ok=True)
        if args[0] == "sudo":
            self.bootstrap_count += 1
            self.received = json.loads(input)
            return "LIGHTEK_SITE=" + json.dumps(dict(site_id=42, application_key=self.key, domain=self.host))

    def verify(self):
        return dict(site_id=42, application_key=self.key, domain=self.host)


class FleetHostedSiteTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = pathlib.Path(self.temp.name)
        for path in ("etc/apache2/sites-available", "etc/apache2/sites-enabled", "var/www/runtime/public"):
            (self.base / path).mkdir(parents=True)
        self.config = dict(domain="new.example.com", name="New application", application_key="12345678-1234-1234-1234-123456789abc",
            owner_email="owner@example.com", certificate_email="owner@example.com", deployment=dict(
                app_root=str(self.base / "var/www/runtime"), app_user=pwd.getpwuid(os.getuid()).pw_name,
                env_file="/etc/lightek/runtime.env", ruby_bin="/home/lightek/.rbenv/versions/3.3.6/bin"))

    def test_application_creation_reuses_runtime_and_configures_only_its_virtual_host(self):
        site = SiteRuntime(self.config, self.base)
        result = site.execute()
        self.assertEqual("succeeded", result["status"])
        self.assertEqual(42, result["site_id"])
        self.assertEqual("owner@example.com", site.received["owner_email"])
        configs = list((self.base / "etc/apache2/sites-available").glob("*.conf"))
        self.assertEqual(2, len(configs))
        ssl = next(path for path in configs if "-ssl" in path.name).read_text()
        self.assertIn('PassengerAppRoot "' + self.config["deployment"]["app_root"] + '"', ssl)
        self.assertIn("ServerName new.example.com", ssl)
        self.assertTrue(any(args[0] == "certbot" for args, _ in site.calls))
        self.assertFalse(any(args[0] in ("docker", "git") or args[:2] == ["systemctl", "stop"] for args, _ in site.calls))

    def test_existing_foreign_hostname_is_not_overwritten(self):
        available = self.base / "etc/apache2/sites-available/other.conf"
        original = "<VirtualHost *:443>\nServerName new.example.com\n</VirtualHost>\n"
        available.write_text(original)
        (self.base / "etc/apache2/sites-enabled/other.conf").symlink_to(available)
        site = SiteRuntime(self.config, self.base)
        with self.assertRaisesRegex(ValueError, "another virtual host"):
            site.execute()
        self.assertEqual(original, available.read_text())
        self.assertEqual(0, site.bootstrap_count)

    def test_certificate_retry_preserves_application_key_and_existing_vhost(self):
        site = SiteRuntime(self.config, self.base)
        site.fail = lambda args: args[0] == "certbot"
        with self.assertRaises(subprocess.CalledProcessError):
            site.execute()
        self.assertEqual(1, len(list((self.base / "etc/apache2/sites-available").glob("*.conf"))))
        site.fail = lambda args: False
        result = site.execute()
        self.assertEqual(self.config["application_key"], result["application_key"])
        self.assertEqual(2, len(list((self.base / "etc/apache2/sites-available").glob("*.conf"))))

    def test_failed_apache_validation_restores_files_and_does_not_reload(self):
        site = SiteRuntime(self.config, self.base)
        site.fail = lambda args: args == ["apache2ctl", "configtest"]
        with self.assertRaises(subprocess.CalledProcessError):
            site.execute()
        self.assertFalse(list((self.base / "etc/apache2/sites-available").glob("*.conf")))
        self.assertFalse(any(args == ["systemctl", "reload", "apache2"] for args, _ in site.calls))

    def test_wrong_public_site_identity_never_marks_setup_complete(self):
        site = SiteRuntime(self.config, self.base)
        with patch.object(site, "verify", return_value={"site_id": 99}), patch.object(hosted.time, "sleep"):
            with self.assertRaisesRegex(ValueError, "identity mismatch"):
                site.execute()

    def test_bootstrap_uses_existing_account_and_dymond_site_ownership_transaction(self):
        self.assertIn('User.find_by!(email_address:', hosted.BOOTSTRAP)
        self.assertIn("DymondSite::Site.transaction", hosted.BOOTSTRAP)
        self.assertIn("site.tenant == owner", hosted.BOOTSTRAP)
        self.assertNotIn("owner.update!", hosted.BOOTSTRAP)
        self.assertNotIn('role: "super_admin"', hosted.BOOTSTRAP)
        subprocess.run(["ruby", "-c"], input=hosted.BOOTSTRAP.encode(), stdout=subprocess.DEVNULL, check=True)

    def test_profile_rejects_hostname_path_and_user_injection(self):
        for config in (dict(self.config, domain="a.example.com; reboot"), dict(self.config, application_key="../../etc/passwd"),
                       dict(self.config, deployment=dict(self.config["deployment"], app_root='/var/www/"bad')),
                       dict(self.config, deployment=dict(self.config["deployment"], app_user="root; reboot"))):
            with self.subTest(config=config), self.assertRaises(ValueError):
                hosted.validate(config)

    def test_public_verification_requires_rendered_homepage_as_well_as_health_record(self):
        site = hosted.HostedSite(self.config, self.base)
        health = json.dumps(dict(site_id=42, application_key=site.key, domain=site.host)).encode()
        def response(body):
            item = MagicMock()
            item.__enter__.return_value = item
            item.status = 200
            item.read.return_value = body
            return item
        for html, valid in ((('name="lightek-application-key" content="' + site.key + '"').encode(), True), (b"wrong homepage", False)):
            opener = MagicMock()
            opener.open.side_effect = [response(health), response(html)]
            with self.subTest(valid=valid), patch.object(hosted.urllib.request, "build_opener", return_value=opener):
                if valid:
                    self.assertEqual(42, site.verify()["site_id"])
                else:
                    with self.assertRaisesRegex(ValueError, "homepage"):
                        site.verify()


if __name__ == "__main__":
    unittest.main()
