"""Exercise the installed mail helpers over real TLS, including queue retention."""
import http.server
import json
import os
from pathlib import Path
import ssl
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[2] / 'lib/scripts'
sys.path.insert(0, str(SCRIPTS))
from fetch_lightek_mail_routes import fetch


class MailHttpsTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        root = Path(self.directory.name)
        self.cert = root / 'cert.pem'
        key = root / 'key.pem'
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
                        '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost',
                        '-keyout', str(key), '-out', str(self.cert)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.token = 'fixture-only-' + 'a' * 64
        self.received = []
        self.fail_delivery = False
        owner = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def authorized(self):
                if self.headers.get('X-Lightek-Mail-Ingress') != owner.token:
                    self.send_response(401)
                    self.end_headers()
                    return False
                return True

            def do_GET(self):
                if not self.authorized():
                    return
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'{"recipients": ["care@client.test"]}')

            def do_POST(self):
                if not self.authorized():
                    return
                if owner.fail_delivery:
                    self.send_response(503)
                    self.end_headers()
                    return
                owner.received.append((self.rfile.read(int(self.headers['Content-Length'])), self.headers['X-Lightek-Mail-Recipients']))
                self.send_response(202)
                self.end_headers()

        self.server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(self.cert, key)
        self.server.socket = context.wrap_socket(self.server.socket, server_side=True)
        thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)
        self.config = {'url': f'https://localhost:{self.server.server_port}/api/lightek-mail/inbound', 'token': self.token}
        self.config_path = root / 'ingress.json'
        self.config_path.write_text(json.dumps(self.config))

    def pipe(self, raw):
        return subprocess.run([sys.executable, str(SCRIPTS / 'lightek_mail_ingress.py'), '--recipient', 'care@client.test', '--config', str(self.config_path)],
                              input=raw, capture_output=True, env=dict(os.environ, SSL_CERT_FILE=str(self.cert)), timeout=15)

    def test_remote_recipient_sync_and_raw_mime_delivery_use_verified_https(self):
        with patch.dict(os.environ, {'SSL_CERT_FILE': str(self.cert)}):
            self.assertEqual(['care@client.test'], fetch(self.config))
        raw = b'From: outside@example.test\r\nTo: other@example.test\r\nSubject: TLS receipt\r\n\r\nOriginal MIME\r\n'
        result = self.pipe(raw)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual([(raw, '["care@client.test"]')], self.received)

    def test_http_outage_and_bad_credential_keep_postfix_message_queued(self):
        self.fail_delivery = True
        self.assertEqual(75, self.pipe(b'original').returncode)
        self.fail_delivery = False
        self.config_path.write_text(json.dumps(dict(self.config, token='wrong-fixture-token')))
        result = self.pipe(b'original')
        self.assertEqual(75, result.returncode)
        self.assertEqual([], self.received)
        self.assertNotIn(self.token.encode(), result.stderr)


if __name__ == '__main__':
    unittest.main()
