import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
class StudioMediaSetupTest(unittest.TestCase):
    def assert_restricted_runtime_probes(self, commands):
        probes=[command for command in commands if command[0]=='run']
        self.assertEqual(len(probes),2)
        node=next(command for command in probes if 'node' in command)
        self.assertEqual(node[-3:],['node','/opt/lightek-editors/movie-render.cjs','--health'])
        self.assertEqual(node[node.index('--memory')+1],'256m')
        blender=next(command for command in probes if 'blender' in command)
        for flag in ['--background','--factory-startup','--disable-autoexec','--python-expr']:
            self.assertIn(flag,blender)
        self.assertEqual(blender[blender.index('--python-exit-code')+1],'1')
        self.assertEqual(blender[blender.index('--memory')+1],'2g')
        for probe in probes:
            with self.subTest(engine=probe[-3:]):
                self.assertIn('--read-only',probe)
                self.assertEqual(probe[probe.index('--network')+1],'none')
                self.assertEqual(probe[probe.index('--cpus')+1],'1')
                self.assertEqual(probe[probe.index('--cap-drop')+1],'ALL')
                self.assertEqual(probe[probe.index('--security-opt')+1],'no-new-privileges')
                self.assertEqual(probe[probe.index('--user')+1],f'{os.getuid()}:{os.getgid()}')
                self.assertNotIn('--volume',probe)

    def test_dependency_installer_builds_the_default_image_and_probes_the_isolated_engine(self):
        with tempfile.TemporaryDirectory() as folder:
            folder=Path(folder)
            docker=folder/'docker'
            docker.write_text('#!/usr/bin/env python3\nimport json,os,sys\nwith open(os.environ["STUDIO_SETUP_TRACE"],"a") as f:f.write(json.dumps(sys.argv[1:])+"\\n")\nif "--python-expr" in sys.argv:print("LIGHTEK_BLENDER_RUNTIME_READY=4.4.0")\nif sys.argv[1:]==["info","--format","{{.NCPU}}"]:print("1")\n')
            docker.chmod(0o755)
            env=os.environ.copy()
            env.pop('STUDIO_ASSET_WORKER_IMAGE',None)
            env.pop('STUDIO_RENDER_WORKER_IMAGE',None)
            env.pop('STUDIO_MEDIA_WORKER_IMAGE',None)
            env.update(PATH=str(folder)+os.pathsep+env['PATH'],STUDIO_SETUP_TRACE=str(folder/'trace'))
            output=subprocess.check_output(['bash',str(ROOT/'lib/scripts/setup_studio_media.sh')],env=env,text=True)
            commands=[json.loads(line) for line in (folder/'trace').read_text().splitlines()]
            self.assertEqual(commands[0],['info'])
            build=next(command for command in commands if command[0]=='build')
            self.assertEqual(build[build.index('--tag')+1],'lightek/studio-media:20261112')
            self.assertEqual(build[-1],str(ROOT/'docker/studio-media'))
            self.assertIn('--label',build)
            self.assert_restricted_runtime_probes(commands)
            self.assertIn('LIGHTEK_BLENDER_RUNTIME_READY=',output)
    def test_reused_image_still_runs_the_restricted_engine_probe(self):
        import importlib.util
        spec=importlib.util.spec_from_file_location("deployment_storage",ROOT/'lib/scripts/deployment_storage.py')
        helper=importlib.util.module_from_spec(spec);spec.loader.exec_module(helper)
        fingerprint=helper.source_digest(ROOT/'docker/studio-media')
        with tempfile.TemporaryDirectory() as directory:
            folder=Path(directory);trace=folder/'trace';binary=folder/'docker'
            binary.write_text('''#!/usr/bin/env python3
import json,os,sys
args=sys.argv[1:]
with open(os.environ['STUDIO_SETUP_TRACE'],'a') as f:f.write(json.dumps(args)+'\\n')
if args[:2]==['image','inspect']:print(json.dumps([{'Config':{'Labels':{'io.lightek.source-sha256':os.environ['TEST_FINGERPRINT']}}}]))
if args==['info','--format','{{.NCPU}}']:print('1')
if '--python-expr' in args:print('LIGHTEK_BLENDER_RUNTIME_READY=4.4.0')
''')
            binary.chmod(0o755)
            env=dict(os.environ,PATH=str(folder)+os.pathsep+os.environ['PATH'],STUDIO_SETUP_TRACE=str(trace),TEST_FINGERPRINT=fingerprint)
            for key in ['STUDIO_ASSET_WORKER_IMAGE','STUDIO_RENDER_WORKER_IMAGE','STUDIO_MEDIA_WORKER_IMAGE']:env.pop(key,None)
            result=subprocess.run(['bash',str(ROOT/'lib/scripts/setup_studio_media.sh')],env=env,capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            calls=[json.loads(line) for line in trace.read_text().splitlines()]
            self.assertFalse(any(c[0]=='build' for c in calls))
            self.assert_restricted_runtime_probes(calls)
            self.assertIn('LIGHTEK_BLENDER_RUNTIME_READY',result.stdout)

    def test_either_failed_runtime_probe_stops_setup(self):
        for engine in ['node','blender']:
            with self.subTest(engine=engine), tempfile.TemporaryDirectory() as directory:
                folder=Path(directory); binary=folder/'docker'
                binary.write_text("#!/usr/bin/env python3\nimport os,sys\nargs=sys.argv[1:]\nif args==['info','--format','{{.NCPU}}']:print('1')\nif args and args[0]=='run' and os.environ['FAIL_ENGINE'] in args:sys.exit(7)\nif '--python-expr' in args:print('LIGHTEK_BLENDER_RUNTIME_READY=4.4.0')\n")
                binary.chmod(0o755)
                env=dict(os.environ,PATH=str(folder)+os.pathsep+os.environ['PATH'],FAIL_ENGINE=engine,
                         STUDIO_ASSET_WORKER_IMAGE='test/studio-media:probe')
                for key in ['STUDIO_RENDER_WORKER_IMAGE','STUDIO_MEDIA_WORKER_IMAGE']:env.pop(key,None)
                result=subprocess.run(['bash',str(ROOT/'lib/scripts/setup_studio_media.sh')],env=env,capture_output=True,text=True)
                self.assertEqual(result.returncode,7)

    def test_normal_deployment_installs_engine_before_starting_workers(self):
        deploy=(ROOT/'lib/scripts/gatekeeper/deploy_project.sh').read_text()
        self.assertLess(deploy.index('bash lib/scripts/setup_studio_media.sh'),deploy.index('systemctl restart "${SIDEKIQ_SERVICE}"'))
        self.assertIn('studio:blender:bootstrap',deploy)
        self.assertLess(deploy.index('setup_studio_docker_access.py'),deploy.index('bash lib/scripts/setup_studio_media.sh'))

    def test_demo_imports_require_explicit_opt_in_and_follow_web_health(self):
        deploy=(ROOT/'lib/scripts/gatekeeper/deploy_project.sh').read_text()
        phase=deploy.split('# Optional library population runs only after',1)[1].split('SHA=',1)[0]
        phase='# Optional library population runs only after'+phase
        self.assertGreater(deploy.index('# Optional library population'),deploy.index('ERROR: healthcheck failed'))
        for value,expected in [(None,False),('0',False),('1',True)]:
            with self.subTest(value=value), tempfile.TemporaryDirectory() as directory:
                trace=Path(directory)/'calls'
                environment=dict(os.environ,APP_DOMAIN='example.com',TRACE=str(trace))
                environment.pop('LIGHTEK_STUDIO_BOOTSTRAP_DEMOS',None)
                if value is not None:environment['LIGHTEK_STUDIO_BOOTSTRAP_DEMOS']=value
                script='set -euo pipefail\nrun_rails() { printf "%s\\n" "$*" >> "$TRACE"; }\n'+phase
                result=subprocess.run(['bash'],input=script,text=True,capture_output=True,env=environment)
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertEqual(trace.exists(),expected)
                if expected:self.assertIn('studio:blender:bootstrap',trace.read_text())
