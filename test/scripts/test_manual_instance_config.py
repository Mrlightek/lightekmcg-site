import contextlib
import importlib.util
import io
import json
import pathlib
import tempfile
import unittest

path = pathlib.Path(__file__).resolve().parents[2] / 'script/lightek/persist_manual_instance_config.py'
spec = importlib.util.spec_from_file_location('instance_config', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class ConfigTest(unittest.TestCase):
    def test_preserves_existing_environment_and_updates_only_vps_settings(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            target, source = root / 'app.env', root / 'settings.json'
            original = 'EXISTING_SETTING=keep\nLIGHTEK_AUTO_VPS_PLAN=old\n'
            target.write_text(original)
            target.chmod(0o640)
            values = dict(LIGHTEK_AUTO_VPS_MONTHLY_COST_CENTS='1200', LIGHTEK_AUTO_VPS_REGION='us-east',
                          LIGHTEK_AUTO_VPS_PLAN='g6-standard-1', LIGHTEK_AUTO_VPS_IMAGE='linode/ubuntu24.04')
            source.write_text(json.dumps(values))
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertTrue(module.persist(source, target))
                self.assertFalse(module.persist(source, target))
            self.assertIn('EXISTING_SETTING=keep\n', target.read_text())
            self.assertEqual(1, target.read_text().count('LIGHTEK_AUTO_VPS_PLAN='))
            self.assertEqual(0o640, target.stat().st_mode & 0o777)
            self.assertEqual(original, target.with_name('app.env.before-manual-paid-instance').read_text())

    def test_rejects_unrelated_configuration_keys_before_writing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            target, source = root / 'app.env', root / 'settings.json'
            target.write_text('EXISTING_SETTING=keep\n')
            source.write_text(json.dumps({'DATABASE_URL': 'unrelated'}))
            with self.assertRaises(RuntimeError):
                module.persist(source, target)
            self.assertEqual('EXISTING_SETTING=keep\n', target.read_text())

if __name__ == '__main__':
    unittest.main()
