import importlib.util
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('media_access',ROOT/'lib/scripts/setup_session_media_access.py')
mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
class SessionMediaAccessTest(unittest.TestCase):
    def test_fixed_helper_and_exact_policy_are_installed(self):
        with tempfile.TemporaryDirectory() as folder,patch.object(mod.os,'chown'),patch.object(mod.subprocess,'run') as verify:
            root=Path(folder);mod.install(ROOT,'lightek',root)
            helper=root/'usr/local/lib/lightek/install_session_media.py'
            self.assertEqual(helper.read_bytes(),(ROOT/'lib/scripts/gatekeeper/install_session_media.py').read_bytes())
            self.assertEqual(stat.S_IMODE(helper.stat().st_mode),0o700)
            policy=root/'etc/sudoers.d/lightek-session-media-lightek'
            text=policy.read_text();self.assertNotIn('*',text);self.assertNotIn(str(ROOT),text)
            self.assertIn('/usr/bin/python3 /usr/local/lib/lightek/install_session_media.py',text)
            self.assertEqual(stat.S_IMODE(policy.stat().st_mode),0o440)
            self.assertEqual(verify.call_args.args[0][:2],['visudo','-cf'])
    def test_helper_symlink_is_not_followed(self):
        with tempfile.TemporaryDirectory() as folder,patch.object(mod.os,'chown'):
            root=Path(folder);parent=root/'usr/local/lib/lightek';parent.mkdir(parents=True)
            victim=root/'victim';victim.write_text('retained')
            (parent/'install_session_media.py').symlink_to(victim)
            with self.assertRaises(ValueError):mod.install(ROOT,'lightek',root)
            self.assertEqual(victim.read_text(),'retained')

    def test_invalid_account_cannot_inject_policy(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(ValueError):mod.install(ROOT,'lightek ALL=(ALL) ALL',Path(folder))
            self.assertEqual(list(Path(folder).iterdir()),[])
    def test_policy_validation_failure_does_not_publish_policy(self):
        with tempfile.TemporaryDirectory() as folder,patch.object(mod.os,'chown'),patch.object(mod.subprocess,'run',side_effect=RuntimeError('invalid policy')):
            root=Path(folder)
            with self.assertRaises(RuntimeError):mod.install(ROOT,'lightek',root)
            self.assertFalse((root/'etc/sudoers.d/lightek-session-media-lightek').exists())
if __name__=='__main__':unittest.main()
