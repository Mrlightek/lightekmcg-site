import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('genesis', ROOT/'lib/scripts/gatekeeper/install_studio_ai.py')
genesis = importlib.util.module_from_spec(spec)
spec.loader.exec_module(genesis)
spec = importlib.util.spec_from_file_location('genesis_access', ROOT/'lib/scripts/setup_studio_ai_access.py')
access = importlib.util.module_from_spec(spec)
spec.loader.exec_module(access)

class Response(io.BytesIO):
    def __init__(self, data, status=200, headers=None):
        super().__init__(data); self.status=status; self.headers=headers or {}

class Opener:
    def __init__(self, response): self.response=response; self.request=None
    def open(self, request, **kwargs): self.request=request; return self.response

class GenesisSetupTest(unittest.TestCase):
    def setUp(self):
        self.config=json.loads((ROOT/'config/studio_ai/packages.json').read_text())
        self.temporary=tempfile.TemporaryDirectory(); self.folder=Path(self.temporary.name)
        self.model={'name':'model.safetensors','bytes':6,'sha256':hashlib.sha256(b'abcdef').hexdigest(),
            'repo':'example/model','revision':'a'*40,'path':'model.safetensors'}
        self.progress=[]
    def tearDown(self): self.temporary.cleanup()
    def progress_fn(self, phase, **values): self.progress.append((phase,values))
    def test_download_size_hash_and_real_progress(self):
        genesis.download(self.model,self.folder,self.progress_fn,Opener(Response(b'abcdef')))
        self.assertEqual(b'abcdef',(self.folder/self.model['name']).read_bytes())
        self.assertEqual(6,self.progress[0][1]['downloaded_bytes'])
        self.assertEqual('verifying_model',self.progress[-1][0])
        # Verified existing model causes no network call.
        genesis.download(self.model,self.folder,self.progress_fn,object())
    def test_resume_partial_and_validate_range(self):
        (self.folder/(self.model['name']+'.part')).write_bytes(b'abc')
        opener=Opener(Response(b'def',206,{'Content-Range':'bytes 3-5/6'}))
        genesis.download(self.model,self.folder,self.progress_fn,opener)
        self.assertEqual('bytes=3-',opener.request.get_header('Range'))
        self.assertEqual(b'abcdef',(self.folder/self.model['name']).read_bytes())
    def test_ignored_range_restarts_file(self):
        (self.folder/(self.model['name']+'.part')).write_bytes(b'abc')
        genesis.download(self.model,self.folder,self.progress_fn,Opener(Response(b'abcdef')))
        self.assertEqual(b'abcdef',(self.folder/self.model['name']).read_bytes())
    def test_hash_mismatch_never_installs_model(self):
        with self.assertRaisesRegex(ValueError,'model_checksum_mismatch'):
            genesis.download(self.model,self.folder,self.progress_fn,Opener(Response(b'xxxxxx')))
        self.assertFalse((self.folder/self.model['name']).exists())
        self.assertFalse((self.folder/(self.model['name']+'.part')).exists())
    def test_existing_model_is_preserved_on_bad_replacement(self):
        (self.folder/self.model['name']).write_bytes(b'old')
        with self.assertRaises(ValueError): genesis.download(self.model,self.folder,self.progress_fn,Opener(Response(b'xxxxxx')))
        self.assertEqual(b'old',(self.folder/self.model['name']).read_bytes())
    def test_symlink_and_oversize_rejected(self):
        (self.folder/self.model['name']).symlink_to(self.folder/'private')
        with self.assertRaisesRegex(ValueError,'unsafe_model_path'): genesis.download(self.model,self.folder,self.progress_fn)
        (self.folder/self.model['name']).unlink()
        with self.assertRaisesRegex(ValueError,'model_size_mismatch'):
            genesis.download(self.model,self.folder,self.progress_fn,Opener(Response(b'abcdefg')))
    def test_capacity_preflight_rejects_small_host_cpu_video_and_missing_gpu(self):
        concept=self.config['packages']['concept'];video=self.config['packages']['video']
        for package,device,memory,available,disk,gpu,runtime,reason in [
            (concept,'cpu',1024,900,100*1024**3,0,False,'insufficient_memory'),
            (concept,'cpu',8192,7000,1024,0,False,'insufficient_disk'),
            (video,'cpu',65536,50000,100*1024**3,0,False,'gpu_required'),
            (video,'cuda',65536,50000,100*1024**3,24576,False,'gpu_unavailable'),
            (video,'cuda',65536,50000,100*1024**3,12000,True,'insufficient_vram')]:
            with self.subTest(reason=reason),self.assertRaisesRegex(ValueError,reason):
                genesis.resources(package,device,memory,available,disk,gpu,runtime)
        genesis.resources(concept,'cpu',8192,7000,100*1024**3)
        genesis.resources(video,'cuda',65536,50000,100*1024**3,24576,True)
    def test_proxy_is_authenticated_specific_order_and_repeatable(self):
        text='<VirtualHost *:443>\nServerName worker.example.test\nProxyPass / http://localhost:3000/\n</VirtualHost>'
        result=genesis.patch_vhost(text,'worker.example.test','a'*64)
        self.assertIn("Require expr",result);self.assertIn('Bearer '+'a'*64,result)
        self.assertLess(result.index('ProxyPass "/lightek-ai/"'),result.index('ProxyPass / '))
        self.assertEqual(result,genesis.patch_vhost(result,'worker.example.test','a'*64))
        with self.assertRaisesRegex(ValueError,'https_vhost_required'): genesis.patch_vhost(text,'other.example.test','a'*64)
        with self.assertRaisesRegex(ValueError,'invalid_credential'): genesis.patch_vhost(text,'worker.example.test','bad\ntext')
    def test_container_binding_limits_models_and_pinned_engine(self):
        cpu=genesis.compose(self.config,'cpu',6)['services']['genesis']
        self.assertEqual(['127.0.0.1:8188:8188'],cpu['ports']);self.assertTrue(cpu['read_only'])
        self.assertIn('--disable-all-custom-nodes',cpu['command']);self.assertIn('--cpu',cpu['command'])
        self.assertEqual('6g',cpu['mem_limit']);self.assertIn(':ro',cpu['volumes'][0])
        dockerfile=genesis.dockerfile(self.config,'cpu')
        self.assertIn(self.config['engine_commit'],dockerfile);self.assertIn('torch==2.7.1',dockerfile)
        self.assertIn('USER 10001:10001',dockerfile)
    def test_status_ownership_and_no_mutation(self):
        payload={'domain':'worker.example.test','owner_domain':'studio.example.test','request_id':'request-12345'}
        state=payload|{'status':'running','phase':'downloading_model','downloaded_bytes':3,'total_bytes':6}
        (self.folder/'state.json').write_text(json.dumps(state))
        with patch.object(genesis,'ROOT',self.folder):
            self.assertEqual(state,genesis.apply(payload|{'action':'status'}))
            with self.assertRaisesRegex(ValueError,'worker_assigned_elsewhere'):
                genesis.apply(payload|{'action':'status','owner_domain':'other.example.test'})
    def test_install_receipt_and_proxy_configuration_without_host_mutation(self):
        runtime=self.folder/'genesis';vhosts=self.folder/'vhosts';vhosts.mkdir()
        vhost=vhosts/'worker.conf';original='<VirtualHost *:443>\nServerName worker.example.test\n</VirtualHost>'
        vhost.write_text(original);vhost.chmod(0o644)
        actual_path=Path
        def paths(value, *args):
            if value=='/proc/meminfo':
                memory=self.folder/'meminfo';memory.write_text('MemTotal: 16777216 kB\nMemAvailable: 12582912 kB\n');return memory
            if value=='/etc/apache2/sites-enabled': return vhosts
            return actual_path(value,*args)
        payload={'action':'install','domain':'worker.example.test','owner_domain':'studio.example.test',
                 'request_id':'install-12345','package_id':'concept','device':'cpu','api_token':'a'*64}
        calls=[]
        with patch.object(genesis,'ROOT',runtime),patch.object(genesis,'Path',side_effect=paths),patch.object(genesis,'catalog',return_value=self.config),\
             patch.object(genesis.os,'geteuid',return_value=0),patch.object(genesis.os,'chown'),\
             patch.object(genesis.shutil,'which',return_value='/usr/bin/docker'),patch.object(genesis.shutil,'disk_usage',return_value=type('Disk',(),{'free':100*1024**3})()),\
             patch.object(genesis,'run',side_effect=lambda *a,**k:calls.append(a)),patch.object(genesis,'download') as download,\
             patch.object(genesis.urllib.request,'build_opener',return_value=Opener(Response(b'{"KSampler":{}}'))):
            receipt=genesis.apply(payload)
        self.assertEqual('ready',receipt['status']);self.assertEqual('engine_and_model_files',receipt['readiness'])
        self.assertNotIn(payload['api_token'],json.dumps(receipt));self.assertEqual(1,download.call_count)
        self.assertIn('Bearer '+payload['api_token'],vhost.read_text());self.assertEqual(0o600,vhost.stat().st_mode&0o777)
        self.assertTrue(any(c[:2]==('docker','build') for c in calls))
        self.assertTrue(any(c[:2]==('apache2ctl','configtest') for c in calls))
        definition=json.loads((runtime/'compose.json').read_text())
        self.assertEqual('6g',definition['services']['genesis']['mem_limit'])

    def test_root_owned_helper_catalog_and_exact_sudo_command(self):
        with patch.object(access.os,'chown'),patch.object(access.subprocess,'run') as command:
            access.install(ROOT,'rails',self.folder)
        helper=self.folder/'usr/local/lib/lightek/install_studio_ai.py'
        catalog=self.folder/'usr/local/lib/lightek/studio-ai-packages.json'
        self.assertEqual(0o700,helper.stat().st_mode&0o777);self.assertEqual(0o600,catalog.stat().st_mode&0o777)
        self.assertEqual(self.config,json.loads(catalog.read_text()))
        policy=(self.folder/'etc/sudoers.d/lightek-studio-ai-rails').read_text()
        self.assertIn('7200s /usr/bin/python3 /usr/local/lib/lightek/install_studio_ai.py',policy)
        self.assertEqual('visudo',command.call_args.args[0][0])

if __name__=='__main__': unittest.main()
