"""WebSocket-to-VNC on a private Unix socket; the guest has no network."""
import os
import socket
from websockify.websocketproxy import LibProxyServer

PATH='/work/.desktop.sock'

class UnixConnection:
    """websockify tunes TCP_NODELAY on every client; Unix sockets need no tuning."""
    def __init__(self, connection): self.connection = connection
    def __getattr__(self, name): return getattr(self.connection, name)
    def setsockopt(self, level, option, value):
        if level == socket.IPPROTO_TCP and option == socket.TCP_NODELAY: return
        return self.connection.setsockopt(level, option, value)

class UnixProxy(LibProxyServer):
    address_family=socket.AF_UNIX
    daemon_threads=True
    def server_bind(self):
        if os.path.lexists(PATH):os.unlink(PATH)
        self.socket.bind(PATH);os.chmod(PATH,0o600)
        self.server_name='localhost';self.server_port=0
    def get_request(self):
        request,_address=self.socket.accept()
        return UnixConnection(request),('localhost',0)

if __name__=='__main__':
    UnixProxy(target_host='127.0.0.1',target_port=5900,web='',listen_port=0).serve_forever()
