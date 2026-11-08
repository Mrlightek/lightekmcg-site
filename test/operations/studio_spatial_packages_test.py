"""Noninteractive TURN package installation and interrupted-install recovery."""
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('spatial_packages', ROOT/'lib/scripts/setup_studio_spatial.py')
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


class PackageTests(unittest.TestCase):
    def test_complete_packages_skip_apt_and_interrupted_packages_retry(self):
        for status, expected in [('install ok installed\n'*2, False),
                                 ('install ok installed\ninstall ok unpacked\n', True)]:
            with self.subTest(status=status), patch.object(setup.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, status)), patch.object(setup, 'run') as run:
                setup.ensure_packages()
                self.assertEqual(run.called, expected)
                if expected:
                    command = run.call_args.args[0]
                    self.assertEqual(command[0], 'apt-get')
                    for option in setup.DPKG_CONFIG_OPTIONS:
                        self.assertIn('Dpkg::Options::='+option, command)
                    self.assertEqual(command[-2:], ['python3-venv', 'coturn'])

    def test_apt_has_noninteractive_environment(self):
        with patch.object(setup.subprocess, 'run') as run:
            setup.run(['apt-get', 'update', '-qq'])
            self.assertEqual(run.call_args.kwargs['env']['DEBIAN_FRONTEND'], 'noninteractive')
            self.assertTrue(run.call_args.kwargs['check'])

    def test_packages_precede_config_and_managed_secret_survives_retry(self):
        with tempfile.TemporaryDirectory() as directory:
            turn = Path(directory)/'turnserver.conf'
            def install():
                self.assertFalse(turn.exists())
                turn.write_text('# Package defaults\n')
            config = {'SPATIAL_TURN_SECRET': 'stable-secret'}
            with patch.object(setup, 'ensure_packages', side_effect=install):
                setup.prepare_turn(config, 'example.com', turn)
            managed = turn.read_bytes()
            self.assertIn(b'static-auth-secret=stable-secret', managed)
            with patch.object(setup, 'ensure_packages') as install:
                setup.prepare_turn({'SPATIAL_TURN_SECRET': 'different'}, 'example.com', turn)
                install.assert_called_once()
            self.assertEqual(turn.read_bytes(), managed)

    def test_package_failure_does_not_write_config_and_operator_config_is_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            turn = Path(directory)/'turnserver.conf'
            config = {'SPATIAL_TURN_SECRET': 'secret'}
            with patch.object(setup, 'ensure_packages', side_effect=RuntimeError('apt failed')):
                with self.assertRaisesRegex(RuntimeError, 'apt failed'):
                    setup.prepare_turn(config, 'example.com', turn)
            self.assertFalse(turn.exists())
            turn.write_text('realm=operator.example\n')
            with patch.object(setup, 'ensure_packages') as install:
                with self.assertRaisesRegex(ValueError, 'refusing to overwrite'):
                    setup.prepare_turn(config, 'example.com', turn)
                install.assert_not_called()
            self.assertEqual(turn.read_text(), 'realm=operator.example\n')

    @unittest.skipUnless(shutil.which('dpkg-deb') and shutil.which('dpkg'), 'requires Debian package tools')
    def test_real_dpkg_recovers_conffile_eof_without_replacing_managed_config(self):
        # Isolated package database/filesystem: never touches host packages.
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            package = folder/'package'
            (package/'DEBIAN').mkdir(parents=True)
            (package/'etc').mkdir()
            (package/'DEBIAN/control').write_text('Package: lightek-turn-fixture\nVersion: 1.0\nArchitecture: all\nMaintainer: Test <test@example.com>\nDescription: Isolated conffile regression\n')
            (package/'DEBIAN/conffiles').write_text('/etc/turnserver.conf\n')
            (package/'etc/turnserver.conf').write_text('# Package defaults\n')
            archive = folder/'fixture.deb'
            subprocess.run(['dpkg-deb', '--build', '--root-owner-group', str(package), str(archive)], check=True, capture_output=True)
            install_root = folder/'root'
            (install_root/'etc').mkdir(parents=True)
            (install_root/'var/lib/dpkg').mkdir(parents=True)
            (install_root/'var/lib/dpkg/status').touch()
            turn = install_root/'etc/turnserver.conf'
            managed = '# LIGHTEK MANAGED SPATIAL TURN\nstatic-auth-secret=keep-me\n'
            turn.write_text(managed)
            command = ['dpkg', '--root='+str(install_root), '--force-not-root']
            environment = dict(os.environ, DEBIAN_FRONTEND='noninteractive')
            broken = subprocess.run([*command, '--install', str(archive)], stdin=subprocess.DEVNULL, capture_output=True, text=True, env=environment)
            self.assertNotEqual(broken.returncode, 0)
            self.assertIn('end of file on stdin at conffile prompt', broken.stderr)
            recovered = subprocess.run([*command, *setup.DPKG_CONFIG_OPTIONS, '--install', str(archive)], stdin=subprocess.DEVNULL, capture_output=True, text=True, env=environment)
            self.assertEqual(recovered.returncode, 0, recovered.stderr)
            self.assertEqual(turn.read_text(), managed)


if __name__ == '__main__':
    unittest.main()
