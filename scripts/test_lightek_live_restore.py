import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import zipfile

import lightek_live_restore as restore


@unittest.skipUnless(sys.platform in ("linux", "darwin"), "Atomic POSIX directory exchange")
class LiveRestoreTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.live = self.root / "live"
        self.live.mkdir()
        (self.live / "previous.txt").write_text("previous data", encoding="utf-8")
        self.staging = self.root / "stage"
        self.staging.mkdir(mode=0o700)
        self.policy = self.root / "authorization.json"
        archive = self.root / "snapshot.zip"
        with zipfile.ZipFile(archive, "w") as backup:
            backup.writestr("restored.txt", "restored data")
        self.sha = hashlib.sha256(archive.read_bytes()).hexdigest()
        context = patch.dict(os.environ, {"LIGHTEK_RECOVERY_ARCHIVE": str(archive),
            "LIGHTEK_RECOVERY_STAGING": str(self.staging), "LIGHTEK_RECOVERY_CUTOVER_AUTHORIZATION": str(self.policy)})
        context.start()
        self.addCleanup(context.stop)

    def arm(self, operation, reference=None, sha=None):
        self.policy.write_text(json.dumps({"operation": operation, "live_directory": str(self.live),
            "sha256": sha or self.sha, "expires_at": int(time.time()) + 300, "reference": reference}), encoding="utf-8")
        self.policy.chmod(0o600)

    def test_switches_live_tree_and_retains_previous_data_for_rollback(self):
        self.arm("cutover")
        result = restore.cutover_backup_restore(self.sha)
        self.assertEqual(result["status"], "activated")
        self.assertFalse(self.policy.exists())
        self.assertEqual((self.live / "restored.txt").read_text(), "restored data")
        reference = result["rollback_reference"]
        self.assertEqual((self.staging / reference / "previous.txt").read_text(), "previous data")
        self.arm("rollback", reference)
        restore.rollback_cutover(self.sha, reference)
        self.assertEqual((self.live / "previous.txt").read_text(), "previous data")
        self.assertEqual((self.staging / reference / "restored.txt").read_text(), "restored data")

    def test_requires_exact_local_authorization(self):
        self.arm("cutover", sha="f" * 64)
        self.assertEqual(restore.cutover_backup_restore(self.sha), {"status": "failed"})
        self.assertEqual((self.live / "previous.txt").read_text(), "previous data")
        self.assertEqual(list(self.staging.iterdir()), [])

    def test_manifest_fails_closed_when_tree_cannot_be_enumerated(self):
        with patch.object(restore.os, "walk", return_value=[]):
            with self.assertRaises(ValueError):
                restore.tree_manifest(self.live)

    def test_failed_live_readback_rolls_back(self):
        self.arm("cutover")
        real_manifest = restore.tree_manifest
        def fail_live_readback(path, durable=False):
            if path == self.live:
                raise OSError("test readback failure")
            return real_manifest(path, durable)
        with patch.object(restore, "tree_manifest", side_effect=fail_live_readback):
            self.assertEqual(restore.cutover_backup_restore(self.sha), {"status": "rolled_back"})
        self.assertEqual((self.live / "previous.txt").read_text(), "previous data")
