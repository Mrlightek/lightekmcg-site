from datetime import datetime, timezone
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

import lightek_native_patch as patching


class NativePatchClientTest(unittest.TestCase):
    def test_macos_requires_matching_native_verification(self):
        target = "Security Update|macos-build|25F81"
        reply = Mock(stdout=json.dumps({"status": "installed", "target": target}))
        with patch.object(Path, "is_file", return_value=True), patch.object(subprocess, "run", return_value=reply) as run:
            self.assertEqual(patching.deploy_macos_patch(target)["status"], "installed")
            self.assertEqual(run.call_args.args[0], ["/usr/bin/sudo", "-n", patching.MACOS_BROKER])
            reply.stdout = json.dumps({"status": "installed", "target": target.replace("25F81", "25F82")})
            self.assertEqual(patching.deploy_macos_patch(target)["status"], "failed")

    def test_windows_submits_one_exact_target_and_accepts_matching_receipt(self):
        target = "a1234567-1234-1234-1234-123456789abc=1"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "Lightek" / "EndpointPatch"
            inbox, outbox = root / "inbox", root / "outbox"
            inbox.mkdir(parents=True)
            outbox.mkdir()
            def run(command, **kwargs):
                self.assertEqual(command[1:], ["/Run", "/TN", patching.WINDOWS_TASK])
                request = json.loads((inbox / "request.json").read_text())
                self.assertEqual(request["target"], target)
                (outbox / "result.json").write_text(json.dumps({"id": request["id"],
                    "result": {"status": "installed", "target": target}}))
            with patch.dict(os.environ, {"ProgramData": directory, "SystemRoot": directory}), patch.object(subprocess, "run", side_effect=run):
                self.assertEqual(patching.deploy_windows_patch(target, datetime.now(timezone.utc)),
                    {"status": "installed", "target": target})

    def test_blocks_invalid_targets_before_starting_brokers(self):
        with patch.object(subprocess, "run") as run:
            self.assertEqual(patching.deploy_windows_patch("invalid", datetime.now(timezone.utc))["status"], "unavailable")
            self.assertEqual(patching.deploy_macos_patch("-a")["status"], "unavailable")
            run.assert_not_called()
