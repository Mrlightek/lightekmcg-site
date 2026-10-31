"""Exercise checkout preparation against real repositories, without a server."""
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
HELPER = ROOT / 'lib/scripts/gatekeeper/prepare_checkout.sh'

class DeployCheckoutTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = pathlib.Path(self.temp.name)
        self.git('init', '-q')
        self.git('config', 'user.email', 'fixture@example.test')
        self.git('config', 'user.name', 'Fixture')
        (self.repo / 'db').mkdir()
        (self.repo / 'db/schema.rb').write_text('original schema\n')
        (self.repo / 'application.rb').write_text('original source\n')
        (self.repo / '.gitignore').write_text('/tmp/\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'Initial')

    def git(self, *args):
        return subprocess.run(['git', '-C', str(self.repo), *args], check=True, capture_output=True, text=True).stdout

    def prepare(self):
        return subprocess.run(['bash', str(HELPER), str(self.repo)], capture_output=True, text=True)

    def test_clean_checkout_needs_no_backup(self):
        self.assertEqual(0, self.prepare().returncode)
        self.assertFalse((self.repo / 'tmp').exists())

    def test_generated_schema_is_preserved_and_source_changes_remain(self):
        (self.repo / 'db/schema.rb').write_text('generated production schema\n')
        (self.repo / 'application.rb').write_text('local source change\n')
        self.assertEqual(0, self.prepare().returncode)
        backups = list((self.repo / 'tmp/deploy-backups').glob('*/schema.rb'))
        self.assertEqual(1, len(backups))
        self.assertEqual('generated production schema\n', backups[0].read_text())
        self.assertEqual('original schema\n', (self.repo / 'db/schema.rb').read_text())
        self.assertEqual('local source change\n', (self.repo / 'application.rb').read_text())
        self.assertEqual(' M application.rb\n', self.git('status', '--porcelain'))
        self.assertEqual(0o700, backups[0].parent.stat().st_mode & 0o777)

    def test_staged_schema_changes_are_never_discarded(self):
        (self.repo / 'db/schema.rb').write_text('intentional staged schema\n')
        self.git('add', 'db/schema.rb')
        self.assertNotEqual(0, self.prepare().returncode)
        self.assertEqual('intentional staged schema\n', (self.repo / 'db/schema.rb').read_text())

    def test_backup_failure_leaves_schema_untouched(self):
        (self.repo / 'db/schema.rb').write_text('keep on failure\n')
        (self.repo / 'tmp').write_text('not a directory')
        self.assertNotEqual(0, self.prepare().returncode)
        self.assertEqual('keep on failure\n', (self.repo / 'db/schema.rb').read_text())

    def test_deleted_schema_is_recoverable_from_patch(self):
        (self.repo / 'db/schema.rb').unlink()
        self.assertEqual(0, self.prepare().returncode)
        patch = next((self.repo / 'tmp/deploy-backups').glob('*/schema.patch'))
        self.git('apply', str(patch))
        self.assertFalse((self.repo / 'db/schema.rb').exists())

if __name__ == '__main__':
    unittest.main()
