import importlib.util
import pathlib
import unittest

path = pathlib.Path(__file__).resolve().parents[2] / "lib/scripts/gatekeeper/install_container_application.py"
spec = importlib.util.spec_from_file_location("container_installer", path)
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)

class ContainerInstallerTest(unittest.TestCase):
    def config(self, **changes):
        return dict(domain="client.example.com", image="ghcr.io/lightek/design@sha256:" + "a" * 64,
                    container_port=3000, launch_id=12, email="owner@example.com", rails_database=True,
                    environment={"API_KEY": "literal$value"}, **changes)

    def state(self):
        return dict(port=20000, database_password="private-db", secret_key_base="private-key")

    def test_rejects_tags_shell_fragments_invalid_ports_and_environment(self):
        for field, value in [("image", "ghcr.io/lightek/app:latest"), ("domain", "example.com;id"),
                             ("container_port", 70000), ("launch_id", "12"), ("environment", {"KEY": {}})]:
            config = self.config()
            config[field] = value
            with self.subTest(field=field), self.assertRaises(ValueError):
                installer.validate(config)

    def test_rails_stack_is_private_persistent_and_keeps_dollars_literal(self):
        compose = installer.compose_config(self.config(), self.state())
        self.assertEqual(["127.0.0.1:20000:3000"], compose["services"]["web"]["ports"])
        self.assertNotIn("ports", compose["services"]["db"])
        self.assertEqual("literal$$value", compose["services"]["web"]["environment"]["API_KEY"])
        self.assertIn("database", compose["volumes"])
        self.assertIn("redis", compose["volumes"])
        self.assertEqual("service_healthy", compose["services"]["web"]["depends_on"]["db"]["condition"])

    def test_optional_sidekiq_worker_shares_only_its_application_storage_and_network(self):
        config = self.config()
        config["rails_worker"] = True
        compose = installer.compose_config(config, self.state())
        worker = compose["services"]["worker"]
        self.assertNotIn("ports", worker)
        self.assertEqual(["bundle", "exec", "sidekiq"], worker["command"])
        self.assertEqual(compose["services"]["web"]["environment"], worker["environment"])

    def test_non_rails_image_keeps_entrypoint_without_database_or_rails_command(self):
        config = self.config()
        config["rails_database"] = False
        compose = installer.compose_config(config, self.state())
        self.assertEqual(["web"], list(compose["services"]))
        self.assertNotIn("command", compose["services"]["web"])

if __name__ == "__main__":
    unittest.main()
