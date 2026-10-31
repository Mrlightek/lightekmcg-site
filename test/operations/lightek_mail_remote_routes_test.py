import importlib.util
import io
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[2] / 'lib/scripts'
sys.path.insert(0, str(SCRIPTS))
import fetch_lightek_mail_routes as routes


class RemoteRoutesTest(unittest.TestCase):
    config = {'url': 'https://lightekmcg.com/api/lightek-mail/inbound', 'token': 'fixture-' + 'a' * 40}

    def fetch(self, payload, status=200):
        class Response(io.BytesIO):
            pass
        response = Response(payload)
        response.status = status
        opener = unittest.mock.Mock()
        opener.open.return_value = response
        with patch.object(routes.urllib.request, 'build_opener', return_value=opener) as build:
            result = routes.fetch(self.config)
            self.assertIsNone(build.call_args.args[0].redirect_request(None))
        request = opener.open.call_args.args[0]
        self.assertEqual('https://lightekmcg.com/api/lightek-mail/routes', request.full_url)
        self.assertEqual(self.config['token'], request.get_header('X-lightek-mail-ingress'))
        return result

    def test_receives_validated_exact_addresses_without_a_local_rails_database(self):
        self.assertEqual(['a@client.test', 'b@client.test'], self.fetch(json.dumps({'recipients': ['b@client.test', 'a@client.test', 'a@client.test']}).encode()))

    def test_rejects_invalid_empty_partial_and_oversize_exports(self):
        for payload in (b'{}', b'{"recipients": []}', b'{"recipients": "a@client.test"}', b'{"recipients": ["a@client.test", "@client.test"]}', b'{"recipients": ["a@client.test\\nother@client.test"]}', b'x' * (4 * 1024 * 1024 + 1)):
            with self.subTest(payload=payload[:80]), self.assertRaises((ValueError, KeyError)):
                self.fetch(payload)

    def test_rejects_non_200_response(self):
        with self.assertRaises(ValueError):
            self.fetch(b'{"recipients": ["a@client.test"]}', status=503)

    def test_validates_destination_before_sending_credentials(self):
        for url in ('http://example.test/api/lightek-mail/inbound', 'https://user:pass@example.test/api/lightek-mail/inbound', 'https://example.test/elsewhere', 'https://example.test/api/lightek-mail/inbound?redirect=yes'):
            with self.subTest(url=url), patch.object(routes.urllib.request, 'build_opener') as opener, self.assertRaises(ValueError):
                routes.fetch(dict(self.config, url=url))
            opener.assert_not_called()


if __name__ == '__main__':
    unittest.main()
