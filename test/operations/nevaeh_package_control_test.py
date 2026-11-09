import importlib.util
import json
import pathlib
import tempfile
import types
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[2]


def module(name, file):
    spec = importlib.util.spec_from_file_location(name, ROOT / file)
    result = importlib.util.module_from_spec(spec);spec.loader.exec_module(result)
    return result


control = module('package_control', 'lib/scripts/nevaeh/package_control.py')
installer = module('package_installer', 'lib/scripts/nevaeh/install_package_control.py')


class Origin:
    def __init__(self, name='Ubuntu', trusted=True):
        self.origin = name;self.trusted = trusted
        self.archive = 'noble';self.component = 'universe';self.site = 'archive.ubuntu.com'


class Version:
    def __init__(self, origins=None):
        self.version = '1.2.3';self.origins = origins if origins is not None else [Origin()]
        self.summary = 'A video tool';self.description = 'Structured documentation'
        self.homepage = 'https://example.com';self.installed_size = 1000;self.size = 500


class Package:
    def __init__(self, name='ffmpeg', origins=None):
        self.name = name;self.candidate = Version(origins);self.installed = None
        self.marked_delete = False;self.is_installed = False
    def mark_install(self, **_kwargs):
        pass


class Cache(dict):
    required_download = 500;required_space = 1000
    def __init__(self, package, changes=None):
        super().__init__({package.name: package});self.package = package;self.changes = changes or [package]
    def clear(self):
        pass
    def get_changes(self):
        return self.changes
    def open(self, _):
        self.package.installed = self.package.candidate;self.package.is_installed = True


class PackageControlTest(unittest.TestCase):
    def test_rejects_option_injection_paths_extra_fields_and_non_install_operations(self):
        for package in ('--allow-unauthenticated', '../evil', 'x;id', '/tmp/app.deb', 'ffmpeg=bad', 'ffmpeg\n-o'):
            with self.assertRaises(ValueError):
                control.validate({'operation': 'install', 'package': package})
        with self.assertRaises(ValueError):
            control.validate({'operation': 'install', 'package': 'ffmpeg', 'options': '-o'})
        with self.assertRaises(ValueError):
            control.validate({'operation': 'remove', 'package': 'postgresql'})

    def test_plan_rejects_untrusted_origins_dependencies_and_removals(self):
        for origins in ([Origin('Unknown')], [Origin('Ubuntu', False)]):
            with self.assertRaises(ValueError):
                control.plan(Cache(Package(origins=origins)), 'ffmpeg')
        root = Package();dependency = Package('dependency', [Origin('Unknown')])
        with self.assertRaises(ValueError):
            control.plan(Cache(root, [root, dependency]), 'ffmpeg')
        dependency = Package('dependency');dependency.marked_delete = True
        with self.assertRaises(ValueError):
            control.plan(Cache(root, [root, dependency]), 'ffmpeg')

    def test_plan_produces_candidate_version_dependency_changes_and_fingerprint(self):
        result = control.plan(Cache(Package()), 'ffmpeg')
        self.assertEqual('1.2.3', result['version'])
        self.assertEqual(500, result['download_bytes'])
        self.assertEqual([{'package': 'ffmpeg', 'version': '1.2.3'}], result['changes'])
        self.assertEqual(64, len(result['sha256']))

    def test_install_retains_apt_authentication_pins_version_and_verifies_result(self):
        package = Package();cache = Cache(package)
        apt = types.SimpleNamespace(Cache=lambda: cache)
        apt_pkg = types.SimpleNamespace(config=types.SimpleNamespace(set=lambda *_: None))
        with patch.object(control, 'ubuntu', return_value={'ID': 'ubuntu'}), patch.dict('sys.modules', {'apt': apt, 'apt_pkg': apt_pkg}), patch.object(control, 'run', return_value='Installed') as run:
            result = control.execute({'operation': 'install', 'package': 'ffmpeg'})
        argv = run.call_args.args[0]
        self.assertIn('ffmpeg=1.2.3', argv)
        self.assertIn('--no-remove', argv)
        self.assertNotIn('--allow-unauthenticated', argv)
        self.assertTrue(result['verified'])
        self.assertEqual('installed', result['status'])

    def test_non_ubuntu_host_is_reported_without_mutation(self):
        with tempfile.TemporaryDirectory() as directory:
            release = pathlib.Path(directory) / 'os-release';release.write_text('ID=debian\n')
            with patch.object(control.pathlib, 'Path', return_value=release), self.assertRaises(ValueError):
                control.ubuntu()

    def test_installer_writes_root_owned_fixed_helper_and_no_argument_sudo_rule(self):
        with tempfile.TemporaryDirectory() as directory:
            base = pathlib.Path(directory);system = base / 'system';app = base / 'app'
            (system / 'etc').mkdir(parents=True);(system / 'etc/os-release').write_text('ID=ubuntu\n')
            source = app / 'lib/scripts/nevaeh/package_control.py';source.parent.mkdir(parents=True);source.write_text('#!/usr/bin/python3 -I\n')
            with patch.object(installer.os, 'geteuid', return_value=0), patch.object(installer.os, 'chown') as chown, patch.object(installer.pwd, 'getpwnam', return_value=types.SimpleNamespace(pw_uid=1001)), patch.object(installer.subprocess, 'run', return_value=types.SimpleNamespace(returncode=0)):
                result = installer.install(app, 'lightek', system_root=system)
            helper = system / 'usr/local/sbin/lightek-package-control'
            self.assertEqual(source.read_bytes(), helper.read_bytes())
            self.assertEqual(0o755, helper.stat().st_mode & 0o777)
            rule = (system / 'etc/sudoers.d/lightek-nevaeh-packages-lightek').read_text()
            self.assertEqual('lightek ALL=(root) NOPASSWD: /usr/local/sbin/lightek-package-control ""\n', rule)
            self.assertTrue(chown.called);self.assertTrue(result['supported'])

    def test_main_deployment_new_instances_and_fleet_updates_include_installer(self):
        for file in ('lib/scripts/gatekeeper/deploy_project.sh', 'script/lightek/native_website_remote.sh', 'lib/scripts/gatekeeper/update_native_installation.py'):
            self.assertIn('nevaeh/install_package_control.py', (ROOT / file).read_text())


if __name__ == '__main__':
    unittest.main()
