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

    def read(self, size=-1):
        return self.body.encode() if size < 0 else self.body.encode()[:size]


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

    def gate(self, **overrides):
        for path in ('/dashboard/pages', '/dashboard/business', '/dashboard/settings', '/dashboard/commerce/orders'):
            self.overrides[path] = Response('https://client-1.example.test/identity/security', 'MFA enrollment')
        proof = dict(version=1, domain=self.config['domain'], release=self.config['release'], site_id=1,
                     owner_email=self.config['owner_email'], password_authenticated=True, mfa_required=True,
                     mfa_enabled=False, mfa_verified=False, session_scope='mfa_enrollment_only')
        proof.update(overrides)
        self.overrides['/identity/onboarding-status'] = Response('https://client-1.example.test/identity/onboarding-status', json.dumps(proof))

    def test_new_owner_pending_mfa_is_installation_evidence_not_full_access(self):
        self.gate()
        result = self.verify()
        self.assertTrue(result['owner_authentication_verified'])
        self.assertTrue(result['owner_onboarding_required'])
        self.assertFalse(result['full_application_dashboard_verified'])
        self.assertEqual('enrollment_required', result['owner_mfa_state'])
        self.assertEqual(4, len(result['verified_dashboard_paths']))

    def test_fake_enrollment_redirect_without_owner_proof_fails(self):
        self.gate(owner_email='other@example.test')
        with self.assertRaises(verifier.PublicVerificationError): self.verify()

    def test_wrong_release_site_or_session_scope_fails(self):
        for changes in [dict(release='stale'), dict(site_id=8), dict(domain='other.test'),
                        dict(password_authenticated=False), dict(mfa_required=False), dict(mfa_enabled=True),
                        dict(mfa_verified=True), dict(session_scope='full')]:
            with self.subTest(changes=changes):
                self.gate(**changes)
                with self.assertRaises(verifier.PublicVerificationError): self.verify()

    def test_partially_unprotected_dashboard_fails(self):
        self.gate()
        self.overrides['/dashboard/settings'] = Response('https://client-1.example.test/dashboard/settings', 'Settings')
        with self.assertRaises(verifier.PublicVerificationError): self.verify()

    def test_same_origin_redirect_guard_rejects_other_hosts(self):
        guard = verifier.SameOriginRedirect(self.config['domain'])
        for url in ['https://other.test/path', 'http://client-1.example.test/path']:
            with self.assertRaises(verifier.PublicVerificationError):
                guard.redirect_request(None, None, 302, '', {}, url)

    def test_tls_failure_is_not_accepted(self):
        with patch.object(verifier.urllib.request, "build_opener") as build:
            build.return_value.open.side_effect = URLError("certificate verify failed")
            with self.assertRaises(URLError):
                verifier.verify_public(self.config)


if __name__ == "__main__":
    unittest.main()
