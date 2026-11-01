import importlib.util,pathlib,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('spatial_setup',ROOT/'lib/scripts/setup_studio_spatial.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class SetupTests(unittest.TestCase):
 def test_stable_instance_secrets_and_generated_services(self):
  first=module.plan('/var/www/lightek','lightek','client.example.com')
  second=module.plan('/var/www/lightek','lightek','client.example.com',first['config'])
  for key in ['STUDIO_SPATIAL_SECRET','SPATIAL_TURN_SECRET','STUDIO_SPATIAL_PORT']:self.assertEqual(first['config'][key],second['config'][key])
  self.assertIn('User=lightek',first['unit']);self.assertIn('SPATIAL_CONTAINER_IMAGE',first['config']);self.assertIn('ws://127.0.0.1:',first['proxy'])
  self.assertNotEqual(first['config']['STUDIO_SPATIAL_SECRET'],module.plan('/var/www/other','lightek','other.example.com')['config']['STUDIO_SPATIAL_SECRET'])
 def test_vhost_insertion_is_idempotent_and_scoped(self):
  text='<VirtualHost *:443>\nServerName client.example.com\nDocumentRoot /var/www/lightek/public\n</VirtualHost>\n<VirtualHost *:443>\nServerName other.example.com\n</VirtualHost>'
  updated=module.inject_vhosts(text,'/var/www/lightek','client.example.com','/etc/lightek/spatial.conf')
  self.assertEqual(updated.count('Include'),1);self.assertEqual(updated,module.inject_vhosts(updated,'/var/www/lightek','client.example.com','/etc/lightek/spatial.conf'))
 def test_all_native_paths_install_streaming_and_paid_packager_includes_dependencies(self):
  for file in ['lib/scripts/gatekeeper/deploy_project.sh','lib/scripts/deploy_lightek_rails.sh','lib/scripts/gatekeeper/update_native_installation.py','script/lightek/native_website_remote.sh']:
   self.assertIn('setup_studio_spatial.py',(ROOT/file).read_text(),file)
  package=(ROOT/'script/lightek/website_deploy.sh').read_text();self.assertIn("'blender','services','docker'",package);self.assertIn("native_website_remote.sh",package)
  native=(ROOT/'script/lightek/native_website_remote.sh').read_text();self.assertIn('PassengerAppRoot',native);self.assertNotIn('dc up -d web',native)

class OverlayTests(unittest.TestCase):
 def test_known_overlays_restore_cleanly_and_refuse_unexpected_edits(self):
  import subprocess,shutil
  overlay_spec=importlib.util.spec_from_file_location('native_overlay',ROOT/'lib/scripts/native_instance_overlay.py');overlay=importlib.util.module_from_spec(overlay_spec);overlay_spec.loader.exec_module(overlay)
  with tempfile.TemporaryDirectory() as directory:
   root=pathlib.Path(directory);(root/'config').mkdir();(root/'script/lightek').mkdir(parents=True);(root/'tmp').mkdir()
   (root/'config/application.rb').write_text('require_relative "boot"\n');(root/'config/routes.rb').write_text('Rails.application.routes.draw do\nend\n');shutil.copy2(ROOT/'script/lightek/website_deploy.sh',root/'script/lightek/website_deploy.sh')
   def git(*args):return subprocess.check_output(['git','-C',str(root),*args],stderr=subprocess.DEVNULL,text=True).strip()
   git('init','-q');git('config','user.name','Test');git('config','user.email','test@example.com');git('add','.');git('commit','-qm','initial')
   original=(root/'config/routes.rb').read_text();overlay.apply(root);self.assertEqual('',git('status','--porcelain','--untracked-files=no'))
   patched=(root/'config/routes.rb').read_text();(root/'config/routes.rb').write_text(patched+'# customer edit\n')
   with self.assertRaises(ValueError):overlay.restore(root)
   self.assertIn('customer edit',(root/'config/routes.rb').read_text());(root/'config/routes.rb').write_text(patched);overlay.restore(root)
   self.assertEqual(original,(root/'config/routes.rb').read_text());self.assertEqual('',git('status','--porcelain','--untracked-files=no'))

if __name__=='__main__':unittest.main()
