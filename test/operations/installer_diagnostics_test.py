import os, subprocess, tempfile, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / 'lib/scripts/gatekeeper/installer_diagnostics.sh'
class InstallerDiagnosticsTest(unittest.TestCase):
    def test_command_failure_reports_only_scope_line_and_original_status(self):
        for scope in ('native', 'bootstrap', 'starter'):
            with self.subTest(scope=scope), tempfile.TemporaryDirectory() as folder:
                script = Path(folder)/'fixture.sh'
                script.write_text('set -euo pipefail\n. "$1"\nlightek_installer_diagnostics "$2"\nprivate_value=NEVER_PRINT_THIS\nbash -c "exit 37"\necho SHOULD_NOT_CONTINUE\n')
                result = subprocess.run(['bash',str(script),str(HELPER),scope], text=True, capture_output=True)
                self.assertEqual(37,result.returncode)
                self.assertEqual(f'LIGHTEK_INSTALLER_FAILURE scope={scope} line=5 exit=37\n', result.stderr)
                self.assertNotIn('NEVER_PRINT_THIS',result.stdout+result.stderr)
                self.assertNotIn('SHOULD_NOT_CONTINUE',result.stdout+result.stderr)
    def test_nested_function_failure_preserves_exit_status_without_command_arguments(self):
        code='set -euo pipefail\n. "$1"\nlightek_installer_diagnostics native\nwork(){ bash -c "exit 29" -- SECRET_ARGUMENT; }\nwork\n'
        result=subprocess.run(['bash','-c',code,'fixture',str(HELPER)],text=True,capture_output=True)
        self.assertEqual(29,result.returncode)
        self.assertIn('scope=native',result.stderr)
        self.assertNotIn('SECRET_ARGUMENT',result.stdout+result.stderr)
    def test_bootstrap_diagnostics_work_when_script_is_downloaded_alone(self):
        source=(ROOT/'lib/scripts/bootstrap_lightek_rails_node.sh').read_text()
        prefix=source.split('[[ "${EUID}" -eq 0 ]]',1)[0]
        result=subprocess.run(['bash','-c',prefix+'\nbash -c "exit 37"\n'],text=True,capture_output=True)
        self.assertEqual(37,result.returncode)
        self.assertIn('LIGHTEK_INSTALLER_FAILURE scope=bootstrap line=',result.stderr)
        self.assertIn('exit=37',result.stderr)
        self.assertNotIn('No such file',result.stderr)
    def test_success_is_quiet_and_scope_cannot_inject_diagnostic_content(self):
        for scope,expected in [('native',0),('native secret-value',2)]:
            result=subprocess.run(['bash','-c','set -euo pipefail; . "$1"; lightek_installer_diagnostics "$2"; true','fixture',str(HELPER),scope],text=True,capture_output=True)
            self.assertEqual(expected,result.returncode)
            self.assertEqual('',result.stdout+result.stderr)
if __name__=='__main__':unittest.main()
