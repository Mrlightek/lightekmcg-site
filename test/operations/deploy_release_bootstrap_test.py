"""Real shell/Git regression for a server that starts on the previous deploy script."""
import base64
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import textwrap
import unittest

ROOT=Path(__file__).resolve().parents[2]
WORKFLOW=ROOT/'.github/workflows/deploy-production.yml'
DEPLOY=ROOT/'lib/scripts/gatekeeper/deploy_project.sh'

class ReleaseSnapshotTest(unittest.TestCase):
    def snapshot_script(self):
        source=WORKFLOW.read_text()
        start=source.index('            DEPLOY_SCRIPT=$(mktemp')
        end=source.index('\n\n            APP_TARGET_SHA',start)
        return 'set -e\n'+textwrap.dedent(source[start:end])+'\nbash "$DEPLOY_SCRIPT"\n'
    def test_workflow_executes_release_snapshot_even_when_installed_script_changes(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);installed=root/'installed.sh';installed.write_text('echo OLD_BODY\n')
            body='printf "echo WRONG_BODY\\n" > "$INSTALLED_SCRIPT"\nprintf "NEW_RELEASE_BODY\\n"\nstat -c %a "$0"\n'
            env=dict(os.environ,TMPDIR=folder,INSTALLED_SCRIPT=str(installed))
            encoded=base64.b64encode(body.encode()).decode()
            result=subprocess.run(['bash','-c',self.snapshot_script(),'bootstrap','main',encoded,'a'*40],env=env,capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual(result.stdout.splitlines(),['NEW_RELEASE_BODY','700'])
            self.assertEqual(list(root.glob('lightek-deploy.*')),[])
            source=WORKFLOW.read_text();self.assertIn('DEPLOY_RELEASE_SCRIPT=$(base64 -w0 lib/scripts/gatekeeper/deploy_project.sh)',source)
            self.assertIn('bash "$DEPLOY_SCRIPT"',source);self.assertIn('APP_TARGET_SHA="$3"',source)
    def test_failed_snapshot_keeps_its_status_and_cleans_up(self):
        with tempfile.TemporaryDirectory() as folder:
            encoded=base64.b64encode(b'exit 23\n').decode()
            result=subprocess.run(['bash','-c',self.snapshot_script(),'bootstrap','main',encoded,'a'*40],env=dict(os.environ,TMPDIR=folder))
            self.assertEqual(result.returncode,23);self.assertEqual(list(Path(folder).iterdir()),[])

class ExactCheckoutTest(unittest.TestCase):
    def test_requested_release_is_used_even_when_remote_main_has_advanced(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);origin=root/'origin';source=root/'source';customer=root/'customer';binary=root/'bin';binary.mkdir()
            def git(path,*args):return subprocess.check_output(['git','-C',str(path),*args],stderr=subprocess.DEVNULL,text=True).strip()
            subprocess.run(['git','init','-q','--bare','--initial-branch=main',str(origin)],check=True)
            subprocess.run(['git','clone','-q',str(origin),str(source)],check=True,stderr=subprocess.DEVNULL)
            git(source,'config','user.name','Release Test');git(source,'config','user.email','test@example.com')
            helper=source/'lib/scripts/gatekeeper';helper.mkdir(parents=True);shutil.copy2(ROOT/'lib/scripts/gatekeeper/prepare_checkout.sh',helper/'prepare_checkout.sh')
            (source/'version').write_text('old');git(source,'add','.');git(source,'commit','-qm','Old release');git(source,'push','origin','main')
            subprocess.run(['git','clone','-q',str(origin),str(customer)],check=True)
            old=git(customer,'rev-parse','HEAD')
            (source/'version').write_text('requested');git(source,'commit','-qam','Requested release');requested=git(source,'rev-parse','HEAD');git(source,'push','origin','main')
            (source/'version').write_text('later');git(source,'commit','-qam','Later release');git(source,'push','origin','main')
            # Exercise the production checkout code without root-only host directories.
            prefix=DEPLOY.read_text().split('echo "[2/8] Bundle"',1)[0]
            prefix=prefix.replace('[[ "$EUID" -eq 0 ]] || { echo "ERROR: run as root"; exit 1; }','# Root privilege is not needed for this isolated Git fixture.')
            prefix=prefix.replace('/var/lib/lightek/fleet/',str(root/'locks')+'/')
            sudo=binary/'sudo';sudo.write_text('#!/bin/bash\nwhile [[ "$1" = -u || "$1" = -H ]];do if [[ "$1" = -u ]];then shift 2;else shift;fi;done\nexec "$@"\n');sudo.chmod(0o755)
            envfile=root/'app.env';envfile.touch()
            env=dict(os.environ,PATH=str(binary)+os.pathsep+os.environ['PATH'],APP_ROOT=str(customer),APP_USER='release-fixture',APP_NAME='fixture',APP_DOMAIN='example.com',ENV_FILE=str(envfile),APP_TARGET_SHA=requested)
            result=subprocess.run(['bash','-c',prefix],env=env,capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stderr);self.assertEqual(git(customer,'rev-parse','HEAD'),requested)
            self.assertEqual((customer/'version').read_text(),'requested')
            bad=dict(env,APP_TARGET_SHA='main; touch SHOULD_NOT_EXIST')
            self.assertNotEqual(subprocess.run(['bash','-c',prefix],env=bad,capture_output=True).returncode,0)
            self.assertFalse((customer/'SHOULD_NOT_EXIST').exists())
            stale=subprocess.run(['bash','-c',prefix],env=dict(env,APP_TARGET_SHA=old),capture_output=True,text=True)
            self.assertNotEqual(stale.returncode,0);self.assertIn('older than the server checkout',stale.stderr)
            self.assertEqual(git(customer,'rev-parse','HEAD'),requested)
if __name__=='__main__':unittest.main()
