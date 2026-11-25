import sys
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib/scripts/gatekeeper"))
import blue_green as rollout

BLUE, GREEN = "a" * 40, "b" * 40


class BlueGreenTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.include = Path(temporary.name) / "active.conf"
        self.journal = self.include.with_name("rollback.conf")
        self.include.write_text(rollout.route("blue", BLUE))
        self.edge = ("blue", BLUE)
        self.workers = {"blue": "active", "green": "inactive"}
        self.history = []
        self.reject = None
        for name, implementation in {
            "command": self.command, "worker_state": self.workers.get,
            "check_worker": self.check_worker, "prove_web": self.probe,
            "reload_edge": self.reload_edge, "prove_same_schema": lambda *_: None,
        }.items():
            mock = patch.object(rollout, name, implementation)
            mock.start()
            self.addCleanup(mock.stop)

    def command(self, *args):
        if "worker@" not in args[-1]:
            return
        slot = args[-1].split("@")[1].split(".")[0]
        self.history.append((args[1], slot))
        self.workers[slot] = "active" if args[1] == "start" else "inactive"
        self.assertLessEqual(list(self.workers.values()).count("active"), 1)

    def check_worker(self, slot, _sha):
        self.assertEqual("active", self.workers[slot])

    def reload_edge(self):
        self.edge = rollout.read_route(self.include)
        self.history.append(("reload", self.edge[0]))

    def probe(self, slot, sha, *, edge=False):
        if self.reject == (slot, edge):
            raise rollout.CutoverError("injected readiness failure")
        if edge:
            self.assertEqual((slot, sha), self.edge)

    def switch(self):
        rollout.switch(self.include, self.journal, "green", GREEN, BLUE)

    def test_bad_inactive_revision_leaves_http_and_worker_untouched(self):
        self.reject = ("green", False)
        with self.assertRaises(rollout.CutoverError):
            self.switch()
        self.assertEqual(("blue", BLUE), self.edge)
        self.assertEqual([], self.history)
        self.assertFalse(self.journal.exists())

    def test_success_switches_http_and_only_one_worker(self):
        self.switch()
        self.assertEqual(("green", GREEN), self.edge)
        self.assertEqual([("stop", "blue"), ("start", "green"), ("reload", "green")], self.history)
        self.assertFalse(self.journal.exists())

    def test_edge_failure_restores_routing_and_worker(self):
        self.reject = ("green", True)
        with self.assertRaises(rollout.CutoverError):
            self.switch()
        self.assertEqual(("blue", BLUE), self.edge)
        self.assertEqual({"blue": "active", "green": "inactive"}, self.workers)
        self.assertFalse(self.journal.exists())

    def test_interrupted_switch_blocks_further_switches_until_recovered(self):
        self.journal.write_text(rollout.route("blue", BLUE))
        self.include.write_text(rollout.route("green", GREEN))
        self.edge = ("green", GREEN)
        self.workers.update(blue="inactive", green="active")
        with self.assertRaises(rollout.CutoverError):
            self.switch()
        rollout.restore(self.include, self.journal)
        self.assertEqual(("blue", BLUE), self.edge)
        self.assertEqual({"blue": "active", "green": "inactive"}, self.workers)

    def test_capacity_refusal_starts_no_services(self):
        with patch.object(rollout, "capacity", return_value={"memory_budget_fits": False}), patch.object(rollout, "command") as command:
            with self.assertRaisesRegex(rollout.CutoverError, "Insufficient host headroom"):
                rollout.prepare(self.include, self.journal, "green", GREEN, 1024, 512)
        command.assert_not_called()
        self.assertEqual(("blue", BLUE), self.edge)

    def test_schema_change_refuses_switch_before_worker_changes(self):
        with patch.object(rollout, "prove_same_schema", side_effect=rollout.CutoverError("schema changed")):
            with self.assertRaisesRegex(rollout.CutoverError, "schema changed"):
                self.switch()
        self.assertEqual([], self.history)
        self.assertFalse(self.journal.exists())

    def test_reboot_starts_only_recorded_slot(self):
        self.workers.update(blue="inactive", green="inactive")
        self.include.write_text(rollout.route("green", GREEN))
        rollout.start_active_slot(self.include, self.journal)
        self.assertEqual([("start", "green")], self.history)
        self.assertEqual({"blue": "inactive", "green": "active"}, self.workers)
