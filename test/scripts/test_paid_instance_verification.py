import importlib.util
import json
import pathlib
import unittest
from unittest.mock import patch
from urllib.parse import urlparse
from urllib.error import URLError

path = pathlib.Path(__file__).resolve().parents[2] / "script/lightek/verify_paid_instance.py"
spec = importlib.util.spec_from_file_location("paid_verifier", path)
verifier = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verifier)


class Response:
    status = 200

    def __init__(self, url, body):
        self.url, self.body = url, body

    def __enter__(self):
        return self

    def __exit__(self, *args):
        pass

    def geturl(self):
        return self.url

    def read(self):
        return self.body.encode()


class VerificationTest(unittest.TestCase):
    def setUp(self):
        self.config = dict(domain="client-1.example.test", release="release-test",
                           owner_email="owner@example.test", owner_password="test-owner-password")
        self.calls = []
        self.overrides = {}

    def open(self, request, timeout):
        path = urlparse(request.full_url).path
        self.calls.append((path, request.data))
        health = json.dumps(dict(domain=self.config["domain"], release=self.config["release"],
                                 sections=3, site_id=1))
        bodies = {"/__lightek/website-health": health,
                  "/": '<meta name="lightek-release" content="release-test">',
                  "/session/new": '<input name="authenticity_token" value="csrf-test">'}
        return self.overrides.get(path, Response(request.full_url, bodies.get(path, "dashboard")))

    def verify(self):
        with patch.object(verifier.urllib.request, "build_opener") as build:
            build.return_value.open.side_effect = self.open
            return verifier.verify_public(self.config)

    def test_healthy_installation_requires_login_and_all_dashboard_probes(self):
        self.assertTrue(self.verify()["full_application_dashboard_verified"])
        self.assertEqual([path for path, _ in self.calls],
                         ["/__lightek/website-health", "/", "/session/new", "/session",
                          "/dashboard/pages", "/dashboard/business", "/dashboard/settings",
                          "/dashboard/commerce/orders"])
        posted = dict(self.calls)["/session"]
        self.assertIn(b"authenticity_token=csrf-test", posted)
        self.assertIn(b"email_address=owner%40example.test", posted)

    def test_login_redirect_to_sign_in_fails(self):
        self.overrides["/dashboard/pages"] = Response("https://client-1.example.test/session/new", "")
        with self.assertRaises(verifier.PublicVerificationError):
            self.verify()

    def test_login_redirect_to_homepage_fails(self):
        self.overrides["/dashboard/pages"] = Response("https://client-1.example.test/", "")
        with self.assertRaises(verifier.PublicVerificationError):
            self.verify()

    def test_missing_full_application_dashboard_fails(self):
        self.overrides["/dashboard/business"] = Response("https://client-1.example.test/", "")
        with self.assertRaises(verifier.PublicVerificationError):
            self.verify()

    def test_placeholder_or_stale_release_fails(self):
        self.overrides["/"] = Response("https://client-1.example.test/", "Coming soon")
        with self.assertRaises(verifier.PublicVerificationError):
            self.verify()

    def test_missing_csrf_token_fails_before_password_submission(self):
        self.overrides["/session/new"] = Response("https://client-1.example.test/session/new", "")
        with self.assertRaises(verifier.PublicVerificationError):
            self.verify()
        self.assertNotIn("/session", [path for path, _ in self.calls])

    def test_tls_failure_is_not_accepted(self):
        with patch.object(verifier.urllib.request, "build_opener") as build:
            build.return_value.open.side_effect = URLError("certificate verify failed")
            with self.assertRaises(URLError):
                verifier.verify_public(self.config)


if __name__ == "__main__":
    unittest.main()
