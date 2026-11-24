import os
from pathlib import Path
import subprocess
import tempfile
import unittest


CHECK = Path(__file__).resolve().parents[2] / "script/lightek/verify_release_promotion.sh"


class ReleasePromotionPreflightTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        shim = self.bin / "curl"
        shim.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys\n"
            "assert sys.argv[-1] == 'https://staging.example.test/gatekeeper/release-promotion'\n"
            "data = json.loads(sys.argv[sys.argv.index('--data') + 1])\n"
            "assert data['profile'] == 'msp'\n"
            "if os.getenv('TEST_PROMOTION_MISMATCH'): data['production_sha'] = '0' * 40\n"
            "print(json.dumps(dict(data, source_sha='1'*40, evidence_digest='2'*64)))\n"
        )
        shim.chmod(0o755)
        self.git("init", "-q")
        self.git("commit", "--allow-empty", "-qm", "Fixture")
        self.environment = {
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "GITHUB_REF": "refs/heads/main",
            "GITHUB_SHA": self.git("rev-parse", "HEAD"),
            "LIGHTEK_RELEASE_ASSURANCE_CANDIDATE_ID": "16",
            "LIGHTEK_RELEASE_PROMOTION_URL": "https://staging.example.test/gatekeeper/release-promotion",
            "LIGHTEK_RELEASE_PROMOTION_TOKEN": "synthetic-token-only",
        }

    def git(self, *arguments):
        return subprocess.check_output(
            ["git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.test", *arguments],
            cwd=self.root,
            text=True,
        ).strip()

    def run_check(self, **overrides):
        return subprocess.run(
            ["bash", CHECK], cwd=self.root, env=self.environment | overrides, capture_output=True, text=True
        )

    def prepare_combined_tree(self):
        for name in (
            "app/models/it_device_maintenance_action.rb",
            "app/services/it_services/enrollment.rb",
            "app/models/it_remote_support_session.rb",
            "app/services/release_assurance/production_promotion.rb",
        ):
            file = self.root / name
            file.parent.mkdir(parents=True, exist_ok=True)
            file.touch()

    def test_combined_tree_requires_configuration_on_main(self):
        self.prepare_combined_tree()
        self.assertNotEqual(0, self.run_check(LIGHTEK_RELEASE_ASSURANCE_CANDIDATE_ID="").returncode)
        self.assertNotEqual(0, self.run_check(GITHUB_REF="refs/heads/develop").returncode)

    def test_verifies_receipt_identity(self):
        self.prepare_combined_tree()
        result = self.run_check()
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn(self.environment["GITHUB_SHA"], result.stdout)
        self.assertNotEqual(0, self.run_check(TEST_PROMOTION_MISMATCH="1").returncode)

    def test_existing_non_msp_release_needs_no_candidate(self):
        self.assertEqual(0, self.run_check(LIGHTEK_RELEASE_ASSURANCE_CANDIDATE_ID="").returncode)
