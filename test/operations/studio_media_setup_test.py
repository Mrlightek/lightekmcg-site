import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
class StudioMediaSetupTest(unittest.TestCase):
    def test_dependency_installer_builds_the_default_image_and_probes_the_isolated_engine(self):
        with tempfile.TemporaryDirectory() as folder:
            folder=Path(folder)
            docker=folder/'docker'
            docker.write_text('#!/usr/bin/env python3\nimport json,os,sys\nwith open(os.environ["STUDIO_SETUP_TRACE"],"a") as f:f.write(json.dumps(sys.argv[1:])+"\\n")\nif "--python-expr" in sys.argv:print("LIGHTEK_BLENDER_RUNTIME_READY=4.0.2")\n')
            docker.chmod(0o755)
            env=os.environ.copy()
            env.pop('STUDIO_ASSET_WORKER_IMAGE',None)
            env.pop('STUDIO_RENDER_WORKER_IMAGE',None)
            env.update(PATH=str(folder)+os.pathsep+env['PATH'],STUDIO_SETUP_TRACE=str(folder/'trace'))
            output=subprocess.check_output(['bash',str(ROOT/'lib/scripts/setup_studio_media.sh')],env=env,text=True)
            commands=[json.loads(line) for line in (folder/'trace').read_text().splitlines()]
            self.assertEqual(commands[0],['info'])
            self.assertIn(['build','--tag','lightek/studio-media:20261101',str(ROOT/'docker/studio-media')],commands)
            probe=next(command for command in commands if command[0]=='run')
            self.assertIn('--disable-autoexec',probe)
            self.assertIn('--read-only',probe)
            self.assertEqual(probe[probe.index('--network')+1],'none')
            self.assertIn('LIGHTEK_BLENDER_RUNTIME_READY=',output)
    def test_normal_deployment_installs_engine_before_starting_workers_and_queues_starter_files(self):
        deploy=(ROOT/'lib/scripts/gatekeeper/deploy_project.sh').read_text()
        self.assertLess(deploy.index('bash lib/scripts/setup_studio_media.sh'),deploy.index('systemctl restart "${SIDEKIQ_SERVICE}"'))
        self.assertIn('studio:blender:bootstrap',deploy)
        self.assertLess(deploy.index('setup_studio_docker_access.py'),deploy.index('bash lib/scripts/setup_studio_media.sh'))
