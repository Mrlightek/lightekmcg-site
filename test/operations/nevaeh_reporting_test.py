import importlib.util
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('reporting', ROOT / 'lib/scripts/gatekeeper/configure_nevaeh_reporting.py')
reporting = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reporting)


class ReportingConfigurationTest(unittest.TestCase):
    def test_environment_update_is_atomic_bounded_to_reporting_keys_and_repeatable(self):
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / 'app.env'
            path.write_text('DATABASE_URL="existing-database"\nNEVAEH_CENTRAL_URL="old"\n')
            values = dict(zip(reporting.KEYS, ('https://central.example.com/gatekeeper/callbacks/nevaeh_escalation', '42', 'a' * 64)))
            self.assertTrue(reporting.write_environment(path, values))
            self.assertFalse(reporting.write_environment(path, values))
            self.assertIn('DATABASE_URL="existing-database"', path.read_text())
            self.assertEqual(1, path.read_text().count('NEVAEH_CENTRAL_URL='))
            self.assertEqual(1, path.read_text().count('NEVAEH_CENTRAL_TOKEN='))

    def test_symlinks_are_rejected_without_changing_target(self):
        with tempfile.TemporaryDirectory() as directory:
            target = pathlib.Path(directory) / 'original'
            target.write_text('original')
            link = pathlib.Path(directory) / 'app.env'
            link.symlink_to(target)
            with self.assertRaises(ValueError):
                reporting.write_environment(link, {})
            self.assertEqual('original', target.read_text())


if __name__ == '__main__':
    unittest.main()
