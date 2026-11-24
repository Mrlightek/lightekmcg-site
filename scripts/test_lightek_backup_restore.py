import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

from lightek_backup_restore import stage_backup_restore


class StagedBackupRestoreTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.archive = self.root / "backup.zip"
        self.staging = self.root / "staging"
        self.staging.mkdir()
        self.settings = {"LIGHTEK_RECOVERY_ARCHIVE": str(self.archive),
                         "LIGHTEK_RECOVERY_STAGING": str(self.staging)}

    def write_archive(self, entries):
        with zipfile.ZipFile(self.archive, "w", compression=zipfile.ZIP_DEFLATED) as backup:
            for name, contents in entries.items():
                backup.writestr(name, contents)
        return hashlib.sha256(self.archive.read_bytes()).hexdigest()

    def test_copies_actual_nested_files_to_a_fresh_directory(self):
        files = {"docs/guide.txt": b"backup guide", "data.csv": b"row,1\n"}
        digest = self.write_archive(files)
        with patch.dict("os.environ", self.settings):
            result = stage_backup_restore(digest)
            repeat = stage_backup_restore(digest)
        self.assertEqual(result["status"], "staged")
        self.assertEqual(result["sha256"], digest)
        self.assertEqual(result["file_count"], 2)
        self.assertEqual(result["byte_count"], sum(map(len, files.values())))
        self.assertNotEqual(result["staging_reference"], repeat["staging_reference"])
        for name, content in files.items():
            self.assertEqual((self.staging / result["staging_reference"] / name).read_bytes(), content)

    def test_digest_mismatch_leaves_staging_empty(self):
        self.write_archive({"data.csv": b"row,1"})
        with patch.dict("os.environ", self.settings):
            self.assertEqual(stage_backup_restore("0" * 64), {"status": "mismatch"})
        self.assertEqual(list(self.staging.iterdir()), [])

    def test_refuses_ambiguous_destination_spellings(self):
        digest = self.write_archive({"docs/One.txt": b"first", "DOCS/Two.txt": b"second"})
        with patch.dict("os.environ", self.settings):
            self.assertEqual(stage_backup_restore(digest), {"status": "failed"})
        self.assertEqual(list(self.staging.iterdir()), [])
