import importlib.util
import pathlib
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "lightek_device_agent", pathlib.Path(__file__).with_name("lightek_device_agent.py"))
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)


class DeviceAgentTest(unittest.TestCase):
    def test_rejects_http(self):
        with patch.dict("os.environ", {
            "LIGHTEK_DEVICE_URL": "http://example.org/gatekeeper/device",
            "LIGHTEK_DEVICE_IDENTIFIER": "test", "LIGHTEK_DEVICE_TOKEN": "secret"
        }):
            with self.assertRaises(ValueError):
                agent.report()

    def test_rejects_credentialed_url(self):
        with patch.dict("os.environ", {
            "LIGHTEK_DEVICE_URL": "https://user:password@example.org/gatekeeper/device",
            "LIGHTEK_DEVICE_IDENTIFIER": "test", "LIGHTEK_DEVICE_TOKEN": "secret"
        }):
            with self.assertRaises(ValueError):
                agent.report()

    def test_linux_metrics_are_bounded(self):
        if agent.sys.platform != "linux":
            self.skipTest("Linux only")
        metrics = agent.collect()
        self.assertIn("disk_percent", metrics)
        self.assertTrue(all(0 <= value <= 100 for value in metrics.values()))
        self.assertNotIn("backup_status", metrics)
        self.assertNotIn("endpoint_protection", metrics)


if __name__ == "__main__":
    unittest.main()
