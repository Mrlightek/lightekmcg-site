import importlib.util
from pathlib import Path
import unittest
spec=importlib.util.spec_from_file_location('media_installer',Path(__file__).resolve().parents[2]/'lib/scripts/gatekeeper/install_session_media.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class MediaInstallerTest(unittest.TestCase):
    def test_configuration_is_bounded_and_does_not_enable_development_keys(self):
        config=module.configuration({'domain':'client.example.test','api_key':'a'*24,'api_secret':'b'*64})
        self.assertEqual(config['rtc']['port_range_end'],50100)
        self.assertEqual(config['keys'],{'a'*24:'b'*64})
        self.assertEqual(config['bind_addresses'],['127.0.0.1'])
    def test_identity_and_credentials_reject_configuration_injection(self):
        for field,value in [('domain','client.example.test\nServerName evil'),('api_key','a\nb'),('api_secret','short')]:
            payload={'domain':'client.example.test','api_key':'a'*24,'api_secret':'b'*64};payload[field]=value
            with self.assertRaises(ValueError):module.configuration(payload)
    def test_proxy_is_idempotent_and_precedes_catch_all(self):
        source='<VirtualHost *:443>\nServerName client.example.test\nProxyPass / http://127.0.0.1:3000/\n</VirtualHost>'
        result=module.patch_vhost(source,'client.example.test')
        self.assertLess(result.index('"/rtc/"'),result.index('ProxyPass / '))
        self.assertEqual(module.patch_vhost(result,'client.example.test'),result)
    def test_other_hosts_and_shared_configurations_are_not_changed(self):
        with self.assertRaises(ValueError):module.patch_vhost('<VirtualHost *:443>\nServerName other.example.test\n</VirtualHost>','client.example.test')
        with self.assertRaises(ValueError):module.patch_vhost('<VirtualHost *:443>\nServerName client.example.test\n</VirtualHost>\n<VirtualHost *:443>\nServerName other.test\n</VirtualHost>','client.example.test')
if __name__=='__main__':unittest.main()
