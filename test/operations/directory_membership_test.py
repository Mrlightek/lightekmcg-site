import importlib.util
from pathlib import Path
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('directory',ROOT/'lib/scripts/gatekeeper/directory_membership.py')
directory=importlib.util.module_from_spec(spec);spec.loader.exec_module(directory)
class DirectoryChecks(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name);self.calls=[];self.joined=False;self.fail_deny=False
        for path in ['usr/sbin','etc/sssd']:(self.root/path).mkdir(parents=True)
        (self.root/'usr/sbin/realm').touch()
        (self.root/'etc/sssd/sssd.conf').write_text('[sssd]\nservices=nss,pam\n[domain/ad.example.com]\ncache_credentials=true\n')
        self.payload={'action':'join','realm':'ad.example.com','binding_id':1,'revision':1,'enabled':True,'principals':['alice@ad.example.com'],'join_user':'delegated','join_password':'never-in-arguments'}
    def tearDown(self):self.temp.cleanup()
    def runner(self,args,secret=None):
        self.calls.append((args,secret))
        if args[:2]==['realm','list']:return 'ad.example.com\n' if self.joined else ''
        if args[:2]==['realm','join']:self.joined=True
        if args[:2]==['realm','deny'] and self.fail_deny:raise RuntimeError('denial failed')
        return ''
    def test_join_denies_all_then_permits_only_explicit_members(self):
        result=directory.apply(self.payload,self.root,self.runner)
        self.assertEqual(result['status'],'succeeded')
        self.assertTrue(result['joined'])
        self.assertEqual(result['principal_count'],1)
        self.assertNotIn('never-in-arguments',str([args for args,_ in self.calls]))
        self.assertIn('never-in-arguments\n',[secret for _,secret in self.calls])
        self.assertIn('cache_credentials = false',(self.root/'etc/sssd/sssd.conf').read_text())
        deny=next(i for i,(args,_) in enumerate(self.calls) if args[:2]==['realm','deny'])
        permit=next(i for i,(args,_) in enumerate(self.calls) if args[:2]==['realm','permit'])
        self.assertLess(deny,permit)
    def test_newer_revocation_cannot_be_overwritten_by_delayed_old_job(self):
        directory.apply(self.payload,self.root,self.runner)
        revoked={**self.payload,'action':'sync','revision':2,'principals':[]}
        directory.apply(revoked,self.root,self.runner)
        count=len(self.calls)
        receipt=directory.apply(self.payload,self.root,self.runner)
        self.assertEqual(receipt['status'],'stale')
        self.assertEqual(len(self.calls),count)
    def test_disabled_unjoined_realm_blocks_an_old_join(self):
        off={**self.payload,'action':'sync','enabled':False,'revision':5,'principals':[]}
        receipt=directory.apply(off,self.root,self.runner)
        self.assertFalse(receipt['joined'])
        self.assertEqual(directory.apply(self.payload,self.root,self.runner)['status'],'stale')
        self.assertFalse(self.joined)
    def test_invalid_principal_and_unmanaged_domain_are_rejected(self):
        with self.assertRaises(ValueError):directory.apply({**self.payload,'principals':['bad; sudo@ad.example.com']},self.root,self.runner)
        self.joined=True
        with self.assertRaises(ValueError):directory.apply(self.payload,self.root,self.runner)
    def test_failed_deny_stops_domain_authentication(self):
        self.fail_deny=True
        with self.assertRaises(RuntimeError):directory.apply(self.payload,self.root,self.runner)
        self.assertIn((['systemctl','stop','sssd'],None),self.calls)
if __name__=='__main__':unittest.main()
