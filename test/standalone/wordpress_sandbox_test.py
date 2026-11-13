import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('sandbox', Path(__file__).parents[2] / 'lib/scripts/gatekeeper/wordpress_sandbox.py')
sandbox = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sandbox)


class WordPressSandboxTest(unittest.TestCase):
    def config(self):
        key = 'a' * 24
        return {'key': key, 'domain': f'wp-test-{key}.lightekmcg.com', 'action': 'install', 'email': 'admin@example.com',
                'credentials': {'admin_username': 'lightek_test', 'admin_password': 'a' * 48, 'database_password': 'b' * 48},
                'plugin_files': {name: 'bundled file' for name in sandbox.PLUGIN_FILES}}

    def test_generated_identity_and_bundle_required(self):
        c = self.config()
        sandbox.validate(c)
        for change in ({'domain': 'lightekmcg.com'}, {'key': '../../app'}, {'action': 'delete_server'}, {'plugin_files': {'../../etc/passwd': 'bad'}}):
            with self.assertRaises(ValueError):
                sandbox.validate(dict(c, **change))

    def test_database_is_private_and_resources_are_bounded(self):
        config = sandbox.compose(self.config(), 34567)
        self.assertNotIn('ports', config['services']['database'])
        self.assertEqual(['127.0.0.1:34567:80'], config['services']['wordpress']['ports'])
        self.assertEqual('192m', config['services']['wordpress']['mem_limit'])
        self.assertNotIn('volumes_from', config['services']['wordpress'])
        self.assertEqual({'database', 'wordpress'}, set(config['volumes']))

    def test_cleanup_only_owns_generated_project_and_certificate(self):
        c = self.config()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / c['key']
            root.mkdir()
            (root / 'compose.json').write_text('{}')
            site = Path(directory) / 'sandbox.conf'
            site.write_text(sandbox.vhost(c, 34567, root / 'challenge'))
            commands = []
            with patch.object(sandbox, 'run', side_effect=lambda args, **kw: commands.append(args)):
                result = sandbox.remove(c, root, {'key': c['key'], 'domain': c['domain']}, ['docker', 'compose', '--project-name', 'lightek-wp-test-' + c['key'], '-f', str(root / 'compose.json')], site)
            self.assertEqual('deleted', result['status'])
            self.assertFalse(root.exists())
            self.assertFalse(site.exists())
            self.assertTrue(any(cmd[-3:] == ['down', '--volumes', '--remove-orphans'] for cmd in commands))
            self.assertFalse(any('prune' in cmd for cmd in commands))
            self.assertFalse(any(cmd[:2] == ['systemctl', 'stop'] for cmd in commands))

    def test_unowned_routing_is_never_removed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            site = root / 'unrelated.conf'
            site.write_text('ServerName lightekmcg.com')
            with patch.object(sandbox, 'run') as run:
                with self.assertRaises(ValueError):
                    sandbox.remove(self.config(), root, {'key': 'a'*24}, [], site)
                run.assert_not_called()
            self.assertTrue(site.exists())

    def test_missing_ownership_does_not_delete_existing_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaises(ValueError):
                sandbox.remove(self.config(), root, None, [], root / 'missing.conf')
            self.assertTrue(root.exists())

    def test_vhost_has_exact_hostname_acme_exclusion_and_tls(self):
        c = self.config()
        text = sandbox.vhost(c, 34567, '/test/challenge', secure=True)
        self.assertIn('ProxyPass /.well-known/acme-challenge/ !', text)
        self.assertIn('RequestHeader set X-Forwarded-Proto "https"', text)
        self.assertIn('/live/lightek-wp-test-' + c['key'] + '/fullchain.pem', text)
        self.assertNotIn('ServerAlias', text)

    def test_bootstrap_prevents_public_install_wizard_and_verifies_plugin(self):
        self.assertLess(sandbox.BOOTSTRAP.index("define('WP_INSTALLING',true)"), sandbox.BOOTSTRAP.index("require '/var/www/html/wp-load.php'"))
        self.assertIn('is_plugin_active', sandbox.BOOTSTRAP)
        self.assertIn('wp_check_password', sandbox.BOOTSTRAP)


if __name__ == '__main__':
    unittest.main()
