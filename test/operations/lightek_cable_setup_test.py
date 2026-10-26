import importlib.util, pathlib, unittest, tempfile, types
source=pathlib.Path(__file__).resolve().parents[2]/'lib/scripts/lightek_cable_setup.py'
spec=importlib.util.spec_from_file_location('cable_setup',source)
setup=importlib.util.module_from_spec(spec);spec.loader.exec_module(setup)

class CableConfigTest(unittest.TestCase):
    def test_only_target_tls_vhost_changes_and_patch_is_idempotent(self):
        http='<VirtualHost *:80>\nServerName lightekmcg.com\nRedirect permanent / https://lightekmcg.com/\n</VirtualHost>'
        other='<VirtualHost *:443>\nServerName client.example\nSSLEngine on\n</VirtualHost>'
        target='<VirtualHost *:443>\nServerName lightekmcg.com\nSSLEngine on\nDocumentRoot /var/www/lightekmcg-site/public\n</VirtualHost>'
        original='\n'.join([http,other,target])
        result,count=setup.patch_vhosts(original,'lightekmcg.com')
        self.assertEqual(1,count)
        self.assertIn(http,result);self.assertIn(other,result)
        self.assertEqual(1,result.count(setup.BEGIN))
        self.assertIn('PassengerEnabled off',result)
        self.assertIn('127.0.0.1:28080/cable',result)
        self.assertEqual((result,1),setup.patch_vhosts(result,'lightekmcg.com'))
    def test_alias_matches_and_unrelated_domains_are_unchanged(self):
        text='<VirtualHost *:443>\nServerName www.lightekmcg.com\nServerAlias lightekmcg.com\n</VirtualHost>'
        self.assertEqual(1,setup.patch_vhosts(text,'lightekmcg.com')[1])
        self.assertEqual((text,0),setup.patch_vhosts(text,'other.test'))
    def test_existing_unmanaged_mapping_is_not_overwritten(self):
        text='<VirtualHost *:443>\nServerName lightekmcg.com\nProxyPass /cable http://example.test/cable\n</VirtualHost>'
        with self.assertRaises(RuntimeError):setup.patch_vhosts(text,'lightekmcg.com')
    def test_customized_managed_block_is_not_overwritten(self):
        text='<VirtualHost *:443>\nServerName lightekmcg.com\n'+setup.proxy_block().replace('28080','28081')+'\n</VirtualHost>'
        with self.assertRaises(RuntimeError):setup.patch_vhosts(text,'lightekmcg.com')
    def test_failed_new_install_restores_config_and_removes_enablement_before_unit(self):
        with tempfile.TemporaryDirectory() as directory:
            config=pathlib.Path(directory)/'site.conf';config.write_bytes(b'new config')
            unit=pathlib.Path(directory)/'test.service';unit.write_bytes(b'new unit')
            calls=[];original=setup.run
            def fake_run(args,check=True):
                if args[:2]==['systemctl','disable']:self.assertTrue(unit.exists())
                calls.append(args);return types.SimpleNamespace(returncode=0)
            setup.run=fake_run
            try:setup.restore({config:b'original config',unit:None},unit,False,False)
            finally:setup.run=original
            self.assertEqual(b'original config',config.read_bytes());self.assertFalse(unit.exists())
            self.assertIn(['systemctl','disable','test.service'],calls)
            self.assertIn(['systemctl','reload','apache2'],calls)
    def test_existing_active_service_is_restored_and_restarted(self):
        with tempfile.TemporaryDirectory() as directory:
            unit=pathlib.Path(directory)/'test.service';unit.write_bytes(b'new unit')
            calls=[];original=setup.run
            setup.run=lambda args,check=True: (calls.append(args) or types.SimpleNamespace(returncode=0))
            try:setup.restore({unit:b'original unit'},unit,True,True)
            finally:setup.run=original
            self.assertEqual(b'original unit',unit.read_bytes())
            self.assertIn(['systemctl','restart','test.service'],calls)
            self.assertNotIn(['systemctl','disable','test.service'],calls)

if __name__=='__main__':unittest.main()
