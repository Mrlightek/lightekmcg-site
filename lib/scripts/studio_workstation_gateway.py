#!/usr/bin/env python3
"""Loopback-only authenticated HTTP/WebSocket gateway for native workstations.

No Docker socket or application secret enters an editing container. Session
metadata is outside its writable mount. Cookies and bootstrap tickets are never
logged or forwarded upstream. Apache exposes only /studio-workstations/.
"""
import argparse
import base64
import hashlib
import hmac
from http.cookies import SimpleCookie, CookieError
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import http.client
import mimetypes
import json
from pathlib import Path
import re
import select
import socket
import time
import threading
import struct
import stat
import os
from urllib.parse import parse_qs, unquote, urlsplit

KEY = re.compile(r'^[a-f0-9]{32}$')


def verify_ticket(token, secret, session, now=None):
    now = int(time.time()) if now is None else now
    try:
        data, signature = token.split('.')
        if len(token) > 2048: raise ValueError('Ticket too large')
        expected = base64.urlsafe_b64encode(hmac.new(secret, data.encode(), hashlib.sha256).digest()).decode().rstrip('=')
        if not hmac.compare_digest(signature, expected): raise ValueError('Invalid signature')
        payload = json.loads(base64.urlsafe_b64decode(data + '=' * (-len(data) % 4)))
        if payload['sid'] != session['session_key'] or payload['uid'] != session['owner_id']: raise ValueError('Wrong session owner')
        if type(payload['exp']) is not int or not now < payload['exp'] <= session['expires_at']: raise ValueError('Expired ticket')
        if session['status'] not in ('ready', 'saving') or session['expires_at'] <= now: raise ValueError('Inactive session')
        return payload
    except (ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        raise PermissionError('Invalid or expired workstation access') from error


def load_session(root, key):
    if not KEY.fullmatch(key): raise PermissionError('Invalid session')
    directory = root / 'sessions' / key
    path = directory / 'session.json'
    if directory.is_symlink() or path.is_symlink() or path.resolve().parent != directory.resolve(): raise PermissionError('Invalid session path')
    try:
        data = json.loads(path.read_text())
        if data['session_key'] != key or not re.fullmatch(r'[a-f0-9]{64}',data.get('container_id','') or ''): raise ValueError('Invalid session container')
        origin = urlsplit(data['origin'])
        if origin.scheme not in ('http', 'https') or not origin.netloc or origin.username or origin.password: raise ValueError('Invalid origin')
        return data
    except (OSError, ValueError, KeyError, TypeError) as error:
        raise PermissionError('Workstation unavailable') from error


class GatewayHandler(BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'
    rbufsize = 0
    timeout = 15
    def log_message(self, *_args): pass  # Bootstrap URL contains a short-lived bearer ticket.
    def reply(self, status, data=b'', headers=None):
        self.send_response(status)
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Referrer-Policy', 'no-referrer')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('X-Content-Type-Options', 'nosniff')
        for key, value in (headers or {}).items(): self.send_header(key, value)
        self.end_headers()
        if self.command != 'HEAD': self.wfile.write(data)
    def do_HEAD(self): self.do_GET()
    def do_GET(self):
        parsed = urlsplit(self.path)
        if parsed.path == '/health':
            return self.reply(200, b'lightek-workstation-gateway')
        parts = parsed.path.split('/', 3)
        try:
            if len(parts) != 4 or parts[1] != 'studio-workstations': raise PermissionError('Unknown path')
            key, suffix = parts[2:]
            decoded = unquote(suffix)
            if '..' in decoded.split('/') or decoded.startswith('/') or '\\' in decoded or '\x00' in decoded: raise PermissionError('Invalid resource path')
            session = load_session(self.server.root, key)
            if self.headers.get('Host', '').lower() != urlsplit(session['origin']).netloc.lower(): raise PermissionError('Wrong origin host')
            cookie_name = 'lightek_workstation_' + key
            if suffix == 'bootstrap':
                token = parse_qs(parsed.query).get('ticket', [''])[0]
                verify_ticket(token, self.server.secret, session)
                secure = '; Secure' if session['origin'].startswith('https://') else ''
                location = '/studio-workstations/' + key + '/vnc.html?autoconnect=1&resize=remote&path=studio-workstations/' + key + '/websockify'
                return self.reply(303, headers={'Location':location, 'Set-Cookie':cookie_name + '=' + token + '; HttpOnly; SameSite=Strict; Path=/studio-workstations/' + key + '/; Max-Age=' + str(max(0, session['expires_at'] - int(time.time()))) + secure})
            cookies = SimpleCookie(); cookies.load(self.headers.get('Cookie', ''))
            token = cookies[cookie_name].value if cookie_name in cookies else ''
            verify_ticket(token, self.server.secret, session)
            if self.headers.get('Upgrade', '').lower() == 'websocket':
                if suffix != 'websockify' or self.headers.get('Origin') != session['origin']: raise PermissionError('Wrong WebSocket origin')
                return self.websocket(session, token)
            # Serve trusted noVNC assets from the HOST, never arbitrary HTML
            # returned by the editable container. Its Python console must not
            # become same-origin application JavaScript execution.
            target = (self.server.static / (suffix or 'vnc.html')).resolve()
            if not target.is_relative_to(self.server.static.resolve()) or not target.is_file():
                return self.reply(404, b'Resource unavailable')
            if target.stat().st_size > 16*1024*1024: raise ValueError('Resource exceeds limit')
            data = target.read_bytes()
            hashes = []
            if target.suffix == '.html':
                for attrs, source in re.findall(rb'<script([^>]*)>(.*?)</script>', data, re.S | re.I):
                    if b'src=' not in attrs.lower() and source.strip():
                        hashes.append("'sha256-" + base64.b64encode(hashlib.sha256(source).digest()).decode() + "'")
            policy = "default-src 'self' data: blob:; script-src 'self' " + ' '.join(hashes) + "; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; connect-src 'self'; frame-ancestors 'self'"
            return self.reply(200, data, {'Content-Type':mimetypes.guess_type(target.name)[0] or 'application/octet-stream','Content-Security-Policy':policy})
        except (PermissionError, KeyError, ValueError, CookieError): return self.reply(403, b'Workstation access denied or expired')
        except (OSError, http.client.HTTPException): return self.reply(502, b'Native desktop is unavailable')
    def websocket(self, session, token):
        work=self.server.root/'sessions'/session['session_key']/'work'
        directory=os.open(work,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
        remote=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM);remote.settimeout(10)
        try:
            info=os.stat('.desktop.sock',dir_fd=directory,follow_symlinks=False)
            if not stat.S_ISSOCK(info.st_mode):raise PermissionError('Invalid desktop socket')
            # Native app roots commonly exceed Linux's 108-byte Unix address
            # limit. Pin the work directory and use its short proc-fd alias.
            remote.connect('/proc/self/fd/'+str(directory)+'/.desktop.sock')
            _pid,uid,_gid=struct.unpack('3i',remote.getsockopt(socket.SOL_SOCKET,socket.SO_PEERCRED,struct.calcsize('3i')))
            if uid!=os.geteuid():raise PermissionError('Wrong desktop socket owner')
        except BaseException:
            remote.close();raise
        finally:os.close(directory)
        try:
            names = ('Sec-WebSocket-Key', 'Sec-WebSocket-Version', 'Sec-WebSocket-Protocol')
            headers = ['GET /websockify HTTP/1.1', 'Host: 127.0.0.1', 'Connection: Upgrade', 'Upgrade: websocket', 'Origin: ' + session['origin']]
            for name in names:
                value = self.headers.get(name)
                if value: headers.append(name + ': ' + value.replace('\r','').replace('\n',''))
            remote.sendall(('\r\n'.join(headers) + '\r\n\r\n').encode())
            data = b''
            while b'\r\n\r\n' not in data:
                chunk = remote.recv(4096)
                if not chunk: raise ConnectionError('Desktop closed handshake')
                data += chunk
                if len(data) > 65536: raise ConnectionError('Handshake too large')
            head, rest = data.split(b'\r\n\r\n', 1)
            if not head.startswith(b'HTTP/1.1 101 ') and not head.startswith(b'HTTP/1.0 101 '):
                return self.reply(502, b'Native desktop rejected WebSocket')
            fields = {}
            for line in head.split(b'\r\n')[1:]:
                if b':' in line:
                    name, value = line.split(b':',1); fields[name.strip().lower()] = value.strip()
            key = self.headers.get('Sec-WebSocket-Key','')
            expected = base64.b64encode(hashlib.sha1((key+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest())
            if fields.get(b'sec-websocket-accept') != expected: return self.reply(502,b'Invalid desktop handshake')
            # Do not forward guest Set-Cookie or other HTTP response headers.
            reply = b'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' + expected + b'\r\n'
            protocol = fields.get(b'sec-websocket-protocol')
            if protocol:
                offered=[v.strip() for v in self.headers.get('Sec-WebSocket-Protocol','').encode().split(b',')]
                if protocol not in offered:return self.reply(502,b'Invalid desktop subprotocol')
                reply += b'Sec-WebSocket-Protocol: '+protocol+b'\r\n'
            self.connection.sendall(reply+b'\r\n'+rest)
            self.close_connection = True
            while True:
                current = load_session(self.server.root, session['session_key'])
                verify_ticket(token, self.server.secret, current)
                readable, _, _ = select.select([self.connection, remote], [], [], 2)
                for stream in readable:
                    chunk = stream.recv(65536)
                    if not chunk: return
                    (remote if stream is self.connection else self.connection).sendall(chunk)
        except (OSError, PermissionError, ValueError): pass
        finally: remote.close()


class GatewayServer(ThreadingHTTPServer):
    daemon_threads=True
    def __init__(self,*args,**kwargs):
        self.slots=threading.BoundedSemaphore(32)
        super().__init__(*args,**kwargs)
    def process_request(self,request,address):
        if not self.slots.acquire(blocking=False):
            request.close();return
        try:super().process_request(request,address)
        except BaseException:self.slots.release();raise
    def process_request_thread(self,request,address):
        try:super().process_request_thread(request,address)
        finally:self.slots.release()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--port', type=int, default=19080)
    args = parser.parse_args()
    secret = (args.root / 'gateway.key').read_bytes()
    if len(secret) < 32: raise ValueError('Gateway key must be at least 32 bytes')
    server = GatewayServer(('127.0.0.1', args.port), GatewayHandler)
    server.daemon_threads = True
    server.root = args.root.resolve(); server.secret = secret; server.static = args.root / 'novnc'
    server.serve_forever()


if __name__ == '__main__': main()
