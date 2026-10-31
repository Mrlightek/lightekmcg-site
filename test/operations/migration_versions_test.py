"""Prevent timestamp collisions across concurrently merged feature branches."""
import collections
import pathlib
import unittest


class MigrationVersionsTest(unittest.TestCase):
    def test_migration_versions_are_unique(self):
        root = pathlib.Path(__file__).resolve().parents[2]
        versions = collections.defaultdict(list)
        for migration in (root / 'db/migrate').glob('[0-9]*_*.rb'):
            versions[migration.name.split('_', 1)[0]].append(migration.name)
        duplicates = {version: files for version, files in versions.items() if len(files) > 1}
        self.assertFalse(duplicates, f'Duplicate migration versions: {duplicates}')


if __name__ == '__main__':
    unittest.main()
