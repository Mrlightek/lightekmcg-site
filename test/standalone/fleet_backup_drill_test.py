import importlib.util
import json
import os
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("backup_drill", ROOT / "lib/scripts/gatekeeper/verify_fleet_backup.py")
drill = importlib.util.module_from_spec(spec)
spec.loader.exec_module(drill)


class BackupDrillTest(unittest.TestCase):
    def setUp(self):
        directory = TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.payload = {"domain": "app.example.test", "target_id": 7, "attempt": 2}
        host = self.root / self.payload["domain"]
        (host / "backups").mkdir(parents=True)
        (host / "managed.json").write_text(json.dumps({"domain": self.payload["domain"]}))
        self.snapshot = host / "backups/fleet-7-2.sql"
        self.snapshot.write_text("fixture backup data")
        self.snapshot.chmod(0o600)

    def test_uses_the_recorded_snapshot_and_an_isolated_local_database_image(self):
        with patch.object(drill.subprocess, "check_output", return_value=f"sha256:{'a'*64}"), \
                patch.object(drill.subprocess, "run", side_effect=self.runtime) as run:
            receipt = drill.restore(self.payload, self.root)
        self.assertEqual(receipt, {**self.payload, "status": "succeeded", "restored_schema": True})
        self.assertEqual(run.call_count, 2)
        self.assertEqual(run.call_args_list[1].args[0][:3], ["docker", "rm", "-f"])

    def runtime(self, args, **options):
        if args[1] == "run":
            self.assertEqual(args[args.index("--network") + 1], "none")
            self.assertEqual(args[args.index("--pull") + 1], "never")
            self.assertIn("--read-only", args)
            self.assertNotIn("--volume", args)
            self.assertIn("public.schema_migrations", args[-1])
            self.assertEqual(options["stdin"].read(), b"fixture backup data")
        return drill.subprocess.CompletedProcess(args, 0, stdout="4\n")

    def test_rejects_a_replaced_or_public_snapshot_before_container_execution(self):
        with patch.object(drill.subprocess, "check_output") as docker:
            self.snapshot.chmod(0o644)
            with self.assertRaises(ValueError):
                drill.restore(self.payload, self.root)
            self.snapshot.unlink()
            self.snapshot.symlink_to(self.root / "unknown.sql")
            with self.assertRaises(OSError):
                drill.restore(self.payload, self.root)
            docker.assert_not_called()

    @unittest.skipUnless(os.environ.get("LIGHTEK_REAL_BACKUP_DRILL") == "1", "Docker PostgreSQL smoke test")
    def test_restores_sql_into_real_isolated_postgresql(self):
        self.snapshot.write_text("CREATE TABLE public.schema_migrations (version text PRIMARY KEY);\n"
                                 "INSERT INTO public.schema_migrations VALUES ('1');\n")
        self.assertTrue(drill.restore(self.payload, self.root)["restored_schema"])


if __name__ == "__main__":
    unittest.main()
