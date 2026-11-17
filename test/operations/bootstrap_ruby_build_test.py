"""Exercise the bootstrap's actual plugin block with real Git and permissions."""
import os
from pathlib import Path
import pwd
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
BOOTSTRAP = ROOT / 'lib/scripts/bootstrap_lightek_rails_node.sh'


class RubyBuildOwnershipTest(unittest.TestCase):
    def test_unwritable_plugin_parent_is_repaired_and_retry_updates_checkout(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            root.chmod(0o755)
            account = pwd.getpwnam('daemon') if os.geteuid() == 0 else pwd.getpwuid(os.geteuid())
            source = root / 'source'
            subprocess.run(['git', 'init', '-q', str(source)], check=True)

            def git(*args):
                return subprocess.run(['git', '-C', str(source), *args], check=True, capture_output=True, text=True)

            git('config', 'user.name', 'Bootstrap Test')
            git('config', 'user.email', 'bootstrap@example.com')
            (source / 'version').write_text('first')
            git('add', '.')
            git('commit', '-qm', 'First')
            rbenv = root / 'rbenv'
            plugins = rbenv / 'plugins'
            plugins.mkdir(parents=True)
            # Root creates a root-owned 755 parent in production. Without root,
            # use a non-writable parent to exercise the same clone failure.
            if os.geteuid() != 0:
                plugins.chmod(0o555)
            binary = root / 'bin'
            binary.mkdir()
            sudo = binary / 'sudo'
            sudo.write_text('#!/usr/bin/env python3\nimport os,pwd,sys\nassert sys.argv[1:4] == ["-u",os.environ["APP_USER"],"-H"]\na=pwd.getpwnam(sys.argv[2])\nif os.geteuid()==0:\n os.setgroups([]);os.setgid(a.pw_gid);os.setuid(a.pw_uid)\nos.execvp(sys.argv[4],sys.argv[4:])\n')
            sudo.chmod(0o755)
            env = dict(os.environ, PATH=str(binary) + os.pathsep + os.environ['PATH'], APP_USER=account.pw_name, RBENV_ROOT=str(rbenv), GIT_CONFIG_COUNT='1', GIT_CONFIG_KEY_0='safe.directory', GIT_CONFIG_VALUE_0=str(source))
            denied = subprocess.run(['sudo', '-u', account.pw_name, '-H', 'git', 'clone', str(source), str(plugins / 'ruby-build')], env=env, capture_output=True, text=True)
            self.assertEqual(denied.returncode, 128, denied.stderr)
            self.assertIn('Permission denied', denied.stderr)
            text = BOOTSTRAP.read_text()
            block = text[text.index('# Bootstrap runs as root;'):text.index('\nPROFILE=')]
            block = block.replace('https://github.com/rbenv/ruby-build.git', source.as_uri())
            result = subprocess.run(['bash', '-euc', block], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((plugins / 'ruby-build/version').read_text(), 'first')
            self.assertEqual(plugins.stat().st_uid, account.pw_uid)
            self.assertEqual(plugins.stat().st_mode & 0o777, 0o755)
            (source / 'version').write_text('second')
            git('commit', '-qam', 'Second')
            result = subprocess.run(['bash', '-euc', block], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((plugins / 'ruby-build/version').read_text(), 'second')


if __name__ == '__main__':
    unittest.main()
