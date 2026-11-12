import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("deployment_storage", ROOT / "lib/scripts/deployment_storage.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class DeploymentStorageTest(unittest.TestCase):
    def test_low_space_reclaims_only_build_cache_and_rechecks(self):
        with patch.object(mod, "filesystems", return_value=[Path("/app")]), patch.object(mod, "shortages", side_effect=[["disk full"], []]), patch.object(mod, "docker", return_value=SimpleNamespace(returncode=0, stdout="reclaimed", stderr="")) as command:
            mod.ensure_space("/app")
            command.assert_called_once_with("builder", "prune", "--all", "--force", check=False)

    def test_persistent_low_space_fails_without_deleting_images_or_data(self):
        with patch.object(mod, "filesystems", return_value=[Path("/app")]), patch.object(mod, "shortages", return_value=["disk full"]), patch.object(mod, "docker", return_value=SimpleNamespace(returncode=0, stdout="0 bytes", stderr="")) as command:
            with self.assertRaisesRegex(RuntimeError, "database files, uploads and mail have been retained"):
                mod.ensure_space("/app")
            self.assertEqual(command.call_count, 1)

    def test_inode_exhaustion_is_detected_even_with_free_bytes(self):
        usage = SimpleNamespace(f_bavail=10000000, f_frsize=4096, f_favail=0)
        with patch.object(mod.os, "statvfs", return_value=usage):
            self.assertEqual(len(mod.shortages([Path("/app")], 2048)), 1)

    def test_matching_source_label_skips_build_and_preserves_cache(self):
        with tempfile.TemporaryDirectory() as folder:
            context = Path(folder)
            (context / "Dockerfile").write_text("FROM ubuntu:24.04\n")
            image = {"Config": {"Labels": {mod.SOURCE_LABEL: mod.source_digest(context)}}}
            with patch.object(mod, "docker", return_value=SimpleNamespace(returncode=0, stdout=json.dumps([image]))), patch.object(mod, "ensure_space") as storage, patch.object(mod.subprocess, "run") as run:
                mod.ensure_image("lightek/studio-media:test", context, folder)
                storage.assert_not_called()
                run.assert_not_called()

    def test_changed_sources_require_headroom_before_build_and_reserve_afterwards(self):
        with tempfile.TemporaryDirectory() as folder:
            context = Path(folder)
            (context / "Dockerfile").write_text("FROM ubuntu:24.04\n")
            image = {"Config": {"Labels": {mod.SOURCE_LABEL: "old-source"}}}
            events = []
            with patch.object(mod, "docker", return_value=SimpleNamespace(returncode=0, stdout=json.dumps([image]))), patch.object(mod, "ensure_space", side_effect=lambda *args: events.append(("storage", args[1]))), patch.object(mod.subprocess, "run", side_effect=lambda *args, **kwargs: events.append(("build", args[0]))) as run:
                mod.ensure_image("lightek/studio-media:test", context, folder)
            self.assertEqual([e[0] for e in events], ["storage", "build", "storage"])
            self.assertEqual(events[0][1], 4096)
            self.assertEqual(events[-1][1], 2048)
            self.assertIn("--label", events[1][1])

    def test_legacy_adoption_requires_clean_sources_older_than_the_image(self):
        image = {"Created": "2026-11-11T20:00:00.123456789Z"}
        with patch.object(mod.subprocess, "run", side_effect=[SimpleNamespace(stdout=""), SimpleNamespace(stdout="1700000000")]):
            self.assertTrue(mod.legacy_source_is_current(Path("/context"), image))
        with patch.object(mod.subprocess, "run", return_value=SimpleNamespace(stdout=" M Dockerfile")):
            self.assertFalse(mod.legacy_source_is_current(Path("/context"), image))
        with patch.object(mod.subprocess, "run", side_effect=[SimpleNamespace(stdout=""), SimpleNamespace(stdout="2000000000")]):
            self.assertFalse(mod.legacy_source_is_current(Path("/context"), image))

    def test_blocked_cold_build_does_not_start_docker_build(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(mod, "docker", return_value=SimpleNamespace(returncode=1, stdout="")), patch.object(mod, "ensure_space", side_effect=RuntimeError("full")), patch.object(mod.subprocess, "run") as run:
            (Path(folder) / "Dockerfile").write_text("FROM ubuntu:24.04\n")
            with self.assertRaisesRegex(RuntimeError, "full"):
                mod.ensure_image("lightek/studio-media:test", folder, folder)
            run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
