import importlib.util,stat,subprocess,unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('docker_access',ROOT/'lib/scripts/setup_studio_docker_access.py');access=importlib.util.module_from_spec(spec);spec.loader.exec_module(access)

class DockerAccessTest(unittest.TestCase):
 def fixture(self,*,installed=True,user_failure=False):
  calls=[];state={'running':False,'member':False}
  def run(args):
   calls.append(args)
   if args[:3]==['systemctl','enable','--now']:state['running']=True
   if args[:3]==['usermod','-a','-G']:state['member']=True
   failed=args[0]=='runuser' and (user_failure or not state['running'] or not state['member'])
   return subprocess.CompletedProcess(args,1 if failed else 0,stdout='',stderr='permission denied' if failed else '')
  return calls,run
 def execute(self,run,*,installed=True,gid=999):
  with patch.object(access.pwd,'getpwnam',return_value=SimpleNamespace(pw_name='lightek')),patch.object(access.shutil,'which',return_value='/usr/bin/docker' if installed else None),patch.object(access.Path,'stat',return_value=SimpleNamespace(st_mode=stat.S_IFSOCK|0o660,st_uid=0,st_gid=gid)),patch.object(access.grp,'getgrgid',return_value=SimpleNamespace(gr_name='docker')),patch.object(access.os,'chmod') as chmod:
   result=access.prepare('lightek',run);chmod.assert_called_once_with(access.SOCKET,0o660);return result
 def test_existing_daemon_access_is_repaired_before_fresh_user_probe(self):
  calls,run=self.fixture();self.assertEqual(self.execute(run),'docker')
  daemon=calls.index(['systemctl','enable','--now','docker']);membership=calls.index(['usermod','-a','-G','docker','lightek']);probe=next(i for i,c in enumerate(calls) if c[0]=='runuser')
  self.assertLess(daemon,membership);self.assertLess(membership,probe)
  self.assertEqual(calls[probe][:4],['runuser','-u','lightek','--']);self.assertIn('DOCKER_HOST=unix:///var/run/docker.sock',calls[probe])
  self.assertFalse(any(c[0]=='apt-get' for c in calls))
 def test_missing_engine_is_installed_and_probe_failure_is_not_ignored(self):
  calls,run=self.fixture();self.execute(run,installed=False);self.assertIn(['apt-get','install','-y','--no-install-recommends','docker.io'],calls)
  calls,run=self.fixture(user_failure=True)
  with self.assertRaisesRegex(RuntimeError,'permission denied'):self.execute(run)
 def test_root_group_is_not_granted_to_the_app(self):
  calls,run=self.fixture()
  with self.assertRaisesRegex(RuntimeError,'group root'):self.execute(run,gid=0)
  self.assertFalse(any(c[0]=='usermod' for c in calls))
 def test_every_native_entrypoint_runs_access_setup_before_media_setup(self):
  for name in ['lib/scripts/gatekeeper/deploy_project.sh','lib/scripts/deploy_lightek_rails.sh','lib/scripts/gatekeeper/update_native_installation.py','script/lightek/native_website_remote.sh']:
   source=(ROOT/name).read_text();self.assertLess(source.index('setup_studio_docker_access.py'),source.index('setup_studio_media.sh'),name)
if __name__=='__main__':unittest.main()
