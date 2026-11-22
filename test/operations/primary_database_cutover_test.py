import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
import uuid


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "lib/scripts/gatekeeper/primary_database_cutover.py"
NAMES = ["--live", "lightek", "--candidate", "lightek_stage", "--retained", "lightek_retained"]


class CutoverArgumentsTest(unittest.TestCase):
    def test_rejects_unconfirmed_switch_or_unrelated_database_names_before_contacting_postgres(self):
        unconfirmed = subprocess.run([sys.executable, SCRIPT, "promote", *NAMES, "--original-oid", "100",
                                      "--replacement-oid", "200", "--cluster-id", "300"], capture_output=True, text=True)
        self.assertEqual(unconfirmed.returncode, 2)
        self.assertIn("Confirm the live database name", unconfirmed.stderr)
        unrelated = subprocess.run([sys.executable, SCRIPT, "inspect", *NAMES[:-1], "unrelated"],
                                   capture_output=True, text=True)
        self.assertEqual(unrelated.returncode, 2)
        self.assertIn("live database prefix", unrelated.stderr)


@unittest.skipUnless(os.environ.get("LIGHTEK_REAL_PRIMARY_CUTOVER") == "1", "Real PostgreSQL container smoke test")
class PostgresCutoverTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.container = f"lightek-cutover-test-{uuid.uuid4().hex}"
        subprocess.run(["docker", "run", "--rm", "-d", "--network", "none", "--name", cls.container,
                        "-e", "POSTGRES_HOST_AUTH_METHOD=trust", "postgres:16"], check=True, stdout=subprocess.DEVNULL)
        cls.addClassCleanup(subprocess.run, ["docker", "rm", "-f", cls.container],
                            stdout=subprocess.DEVNULL, check=False)
        for _ in range(30):
            ready = subprocess.run(["docker", "exec", cls.container, "cat", "/proc/1/comm"],
                                   check=True, capture_output=True, text=True)
            if ready.stdout.strip() == "postgres":
                probe = subprocess.run(["docker", "exec", cls.container, "pg_isready", "-q", "-U", "postgres"])
                if probe.returncode == 0:
                    break
            time.sleep(1)
        else:
            raise RuntimeError("Fixture PostgreSQL never became ready")

        cls.psql("postgres", "CREATE DATABASE lightek")
        cls.psql("postgres", "CREATE DATABASE lightek_stage")
        cls.psql("lightek", "CREATE TABLE schema_migrations(version text); INSERT INTO schema_migrations VALUES ('1');"
                           "CREATE TABLE users(marker text); INSERT INTO users VALUES ('replacement');")
        cls.archive = subprocess.check_output(["docker", "exec", cls.container, "pg_dump", "-U", "postgres",
                                               "--format=custom", "--dbname", "lightek"])
        cls.psql("lightek", "UPDATE users SET marker = 'original'")

    @classmethod
    def psql(cls, database, sql):
        return subprocess.check_output(["docker", "exec", cls.container, "psql", "-XqAt", "-U", "postgres",
                                        "-d", database, "-v", "ON_ERROR_STOP=1", "-c", sql], text=True).strip()

    def test_fence_promote_reopen_and_reverse_preserve_both_databases(self):
        with tempfile.TemporaryDirectory() as directory:
            wrapper = Path(directory) / "psql"
            wrapper.write_text('#!/bin/sh\nexec docker exec -i "$CUTOVER_CONTAINER" psql -U postgres "$@"\n')
            wrapper.chmod(0o755)
            restorer = Path(directory) / "pg_restore"
            restorer.write_text('#!/bin/sh\nexec docker exec -i "$CUTOVER_CONTAINER" pg_restore -U postgres "$@"\n')
            restorer.chmod(0o755)
            archive = Path(directory) / "fixture.dump"
            archive.write_bytes(self.archive)
            env = {**os.environ, "PATH": directory + os.pathsep + os.environ["PATH"], "CUTOVER_CONTAINER": self.container}

            def run(action, *flags, accepted=True):
                output = subprocess.run([sys.executable, SCRIPT, action, *NAMES, *flags],
                                        env=env, capture_output=True, text=True)
                if accepted:
                    self.assertEqual(output.returncode, 0, output.stderr)
                    return json.loads(output.stdout)
                self.assertNotEqual(output.returncode, 0, output.stdout)
                return output.stderr

            inventory = run("inspect")
            databases = inventory["databases"]
            preparation = ("--original-oid", str(databases["lightek"]["oid"]), "--replacement-oid",
                           str(databases["lightek_stage"]["oid"]), "--cluster-id", inventory["cluster_id"],
                           "--confirm", "lightek_stage", "--archive", str(archive))
            proof = run("prepare", *preparation)
            self.assertEqual(run("verify")["schema_fingerprint"], proof["schema_fingerprint"])
            self.assertIn("empty candidate", run("prepare", *preparation, accepted=False))
            original, replacement = proof["original_oid"], proof["replacement_oid"]
            ids = ("--original-oid", str(original), "--replacement-oid", str(replacement), "--confirm", "lightek")
            approval = (*ids, "--cluster-id", proof["cluster_id"])
            wrong_cluster = (*ids, "--cluster-id", "1")
            self.assertIn("cluster identity changed", run("fence", *wrong_cluster, "--phase", "original", accepted=False))
            self.assertIn("Fence both databases", run("promote", *approval, accepted=False))
            fenced = run("fence", *approval, "--phase", "original")["databases"]
            self.assertFalse(fenced["lightek"]["allows_connections"])
            self.assertFalse(fenced["lightek_stage"]["allows_connections"])
            for _ in range(2):
                switched = run("promote", *approval)["databases"]
                self.assertEqual(switched["lightek"]["oid"], replacement)
                self.assertEqual(switched["lightek_retained"]["oid"], original)
                self.assertNotIn("lightek_stage", switched)
                self.assertFalse(switched["lightek"]["allows_connections"])
            run("open", *approval, "--phase", "replacement")
            self.assertEqual(self.psql("lightek", "SELECT marker FROM users"), "replacement")
            self.assertIn("Fence both databases", run("reverse", *approval, accepted=False))
            run("fence", *approval, "--phase", "replacement")
            reversed_map = run("reverse", *approval)["databases"]
            self.assertEqual(reversed_map["lightek"]["oid"], original)
            self.assertEqual(reversed_map["lightek_stage"]["oid"], replacement)
            run("open", *approval, "--phase", "original")
            self.assertEqual(self.psql("lightek", "SELECT marker FROM users"), "original")


if __name__ == "__main__":
    unittest.main()
