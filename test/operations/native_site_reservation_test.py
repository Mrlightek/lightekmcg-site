import importlib.util, json, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('native_reservation',ROOT/'lib/scripts/gatekeeper/native_site_reservation.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class NativeSiteReservationTest(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.base=Path(self.temp.name)/'member.example.com'
        self.settings={'domain':'member.example.com','owner_email':'owner@example.com','owner_password':'DO_NOT_STORE'}
    def test_identity_survives_bootstrap_failure_and_retry(self):
        module.reserve(self.base,self.settings,'project-one')
        (self.base/'releases'/('a'*20)).mkdir(parents=True)
        module.reserve(self.base,self.settings,'project-one')
        record=json.loads((self.base/'managed.json').read_text())
        self.assertTrue(record['bootstrap_pending'])
        self.assertEqual('owner@example.com',record['owner_email'])
        self.assertNotIn('owner_password',record)
        self.assertNotIn('DO_NOT_STORE',(self.base/'managed.json').read_text())
    def test_old_interrupted_empty_bootstrap_is_recoverable(self):
        (self.base/'releases'/('a'*20)).mkdir(parents=True)
        module.reserve(self.base,self.settings,'project-one')
        self.assertTrue((self.base/'managed.json').is_file())
    def test_unowned_data_and_nonempty_release_are_preserved_and_rejected(self):
        for relative in ('.env','storage/original.mp4','releases/'+('a'*20)+'/Gemfile'):
            with self.subTest(relative=relative),tempfile.TemporaryDirectory() as folder:
                base=Path(folder)/'site';data=base/relative;data.parent.mkdir(parents=True);data.write_text('preserve me')
                with self.assertRaises(ValueError):module.reserve(base,self.settings,'project-one')
                self.assertEqual('preserve me',data.read_text());self.assertFalse((base/'managed.json').exists())
    def test_mismatched_owner_domain_or_project_cannot_adopt_a_reserved_site(self):
        module.reserve(self.base,self.settings,'project-one')
        before=(self.base/'managed.json').read_bytes()
        for settings,project in [(dict(self.settings,owner_email='other@example.com'),'project-one'),(dict(self.settings,domain='other.example.com'),'project-one'),(self.settings,'project-two')]:
            with self.assertRaises(ValueError):module.reserve(self.base,settings,project)
            self.assertEqual(before,(self.base/'managed.json').read_bytes())
    def test_symlinked_base_release_and_record_are_rejected(self):
        for kind in ('base','release','record'):
            with self.subTest(kind=kind),tempfile.TemporaryDirectory() as folder:
                root=Path(folder);outside=root/'outside';outside.mkdir();base=root/'site'
                if kind=='base':base.symlink_to(outside,target_is_directory=True)
                elif kind=='release':
                    (base/'releases').mkdir(parents=True);(base/'releases'/('a'*20)).symlink_to(outside,target_is_directory=True)
                else:
                    base.mkdir();target=outside/'record';target.write_text('{}');(base/'managed.json').symlink_to(target)
                with self.assertRaises(ValueError):module.reserve(base,self.settings,'project-one')
    def test_existing_owned_legacy_identity_is_not_rewritten(self):
        self.base.mkdir();record={'domain':self.settings['domain'],'owner_email':self.settings['owner_email'],'project':'legacy-compose-project','adapter':'docker','version':1}
        (self.base/'managed.json').write_text(json.dumps(record));before=(self.base/'managed.json').read_bytes()
        module.reserve(self.base,self.settings,'project-one')
        self.assertEqual(before,(self.base/'managed.json').read_bytes())
if __name__=='__main__':unittest.main()
