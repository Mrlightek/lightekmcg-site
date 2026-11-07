import base64
import hashlib
import hmac
from http.client import HTTPMessage
import importlib.util
import io
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[2]
def module(name):
    spec=importlib.util.spec_from_file_location(name,ROOT/'lib/scripts'/f'{name}.py');value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value

gateway=module('studio_workstation_gateway');installer=module('install_studio_workstation');cleaner=module('studio_workstation_cleanup')

class WorkstationGatewayTest(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name);self.key='a'*32;self.secret=b'test-key'*8
        self.data={'session_key':self.key,'owner_id':12,'site_id':4,'status':'ready','port':21000,'expires_at':2000,'origin':'https://studio.test','container_id':'b'*64}
        path=self.root/'sessions'/self.key;path.mkdir(parents=True);(path/'session.json').write_text(json.dumps(self.data));(self.root/'novnc').mkdir();(self.root/'novnc/vnc.html').write_text('<script src="app/ui.js"></script><main>Trusted noVNC</main>')
    def tearDown(self):self.tmp.cleanup()
    def ticket(self,**overrides):
        payload={'sid':self.key,'uid':12,'exp':1900,**overrides};data=base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip('=');signature=base64.urlsafe_b64encode(hmac.new(self.secret,data.encode(),hashlib.sha256).digest()).decode().rstrip('=');return data+'.'+signature
    def handler(self,path,cookie=None,origin=None):
        h=object.__new__(gateway.GatewayHandler);h.server=SimpleNamespace(root=self.root,static=self.root/'novnc',secret=self.secret);h.path=path;h.command='GET';h.headers=HTTPMessage();h.headers['Host']='studio.test'
        if cookie:h.headers['Cookie']='lightek_workstation_'+self.key+'='+cookie
        if origin:h.headers['Origin']=origin
        h.reply=lambda status,data=b'',headers=None:setattr(h,'result',(status,data,headers or {}))
        return h
    def test_tickets_reject_wrong_owner_session_expiration_signature_and_revocation(self):
        self.assertEqual(gateway.verify_ticket(self.ticket(),self.secret,self.data,now=1000)['uid'],12)
        for token in [self.ticket(uid=13),self.ticket(sid='c'*32),self.ticket(exp=999),self.ticket(exp=2200),self.ticket()+'x','bad']:
            with self.assertRaises(PermissionError):gateway.verify_ticket(token,self.secret,self.data,now=1000)
        for status in ['stopped','expired','failed','starting']:
            with self.assertRaises(PermissionError):gateway.verify_ticket(self.ticket(),self.secret,{**self.data,'status':status},now=1000)
    def test_bootstrap_sets_scoped_http_only_cookie_and_removes_token_from_location(self):
        h=self.handler('/studio-workstations/'+self.key+'/bootstrap?ticket='+self.ticket())
        with patch.object(gateway.time,'time',return_value=1000):h.do_GET()
        self.assertEqual(h.result[0],303);cookie=h.result[2]['Set-Cookie']
        for flag in ['HttpOnly','SameSite=Strict','Secure','Path=/studio-workstations/'+self.key+'/']:self.assertIn(flag,cookie)
        self.assertNotIn(self.ticket(),h.result[2]['Location'])
    def test_assets_are_authenticated_trusted_host_files_not_container_html(self):
        path='/studio-workstations/'+self.key+'/vnc.html'
        h=self.handler(path)
        with patch.object(gateway.time,'time',return_value=1000):h.do_GET()
        self.assertEqual(h.result[0],403)
        h=self.handler(path,self.ticket())
        with patch.object(gateway.time,'time',return_value=1000),patch.object(gateway.http.client,'HTTPConnection',side_effect=AssertionError('Guest HTML must never be proxied')):h.do_GET()
        self.assertEqual(h.result[0],200);self.assertIn(b'Trusted noVNC',h.result[1]);self.assertIn("frame-ancestors 'self'",h.result[2]['Content-Security-Policy'])
        for suffix in ['../gateway.key','%2e%2e/gateway.key','/etc/passwd']:
            h=self.handler('/studio-workstations/'+self.key+'/'+suffix,self.ticket())
            with patch.object(gateway.time,'time',return_value=1000):h.do_GET()
            self.assertEqual(h.result[0],403)
    def test_cross_origin_websocket_and_wrong_hostname_are_denied(self):
        h=self.handler('/studio-workstations/'+self.key+'/websockify',self.ticket(),'https://attacker.test');h.headers['Upgrade']='websocket'
        with patch.object(gateway.time,'time',return_value=1000):h.do_GET()
        self.assertEqual(h.result[0],403)
        h=self.handler('/studio-workstations/'+self.key+'/vnc.html',self.ticket());h.headers.replace_header('Host','other-site.test')
        with patch.object(gateway.time,'time',return_value=1000):h.do_GET()
        self.assertEqual(h.result[0],403)
    def test_installer_scopes_proxy_to_application_vhosts_and_is_idempotent(self):
        root=Path('/var/www/lightek');conf=Path('/etc/apache2/conf-available/workstation.conf')
        original='<VirtualHost *:443>\nServerName studio.test\nDocumentRoot /var/www/lightek/public\n</VirtualHost>\n<VirtualHost *:443>\nServerName unrelated.test\nDocumentRoot /var/www/other/public\n</VirtualHost>'
        updated,count=installer.patch_vhosts(original,root,'studio.test',conf)
        self.assertEqual(count,1);self.assertEqual(updated.count('IncludeOptional'),1)
        again,count=installer.patch_vhosts(updated,root,'studio.test',conf);self.assertEqual(updated,again)
        a=installer.configuration(root,'lightek','lightek',root/'storage');b=installer.configuration(Path('/var/www/client'),'client','client',Path('/var/www/client/storage'))
        self.assertNotEqual(a['service'],b['service']);self.assertNotEqual(a['port'],b['port']);self.assertIn('127.0.0.1:',a['apache']);self.assertIn('OnUnitActiveSec=1min',a['cleanup_timer'])
    def test_cleanup_checks_container_ownership_and_revokes_expired_sessions(self):
        calls=[]
        def command(args,**kwargs):
            calls.append(args);return SimpleNamespace(returncode=0,stdout=self.key+'\n')
        cleaner.cleanup(self.root,now=2001,command=command)
        self.assertTrue(any(args[:3]==['docker','rm','-f'] for args in calls))
        data=json.loads((self.root/'sessions'/self.key/'session.json').read_text());self.assertEqual(data['status'],'expired');self.assertIsNone(data['port'])
        data.update(status='ready',port=21000);(self.root/'sessions'/self.key/'session.json').write_text(json.dumps(data));calls=[]
        cleaner.cleanup(self.root,now=2001,command=lambda args,**kw:(calls.append(args) or SimpleNamespace(returncode=0,stdout='someone-else')))
        self.assertFalse(any(args[:3]==['docker','rm','-f'] for args in calls))

if __name__=='__main__':unittest.main()
