"""Validate generated workstation services with systemd's real unit parser."""
import getpass
import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('installer',ROOT/'lib/scripts/install_studio_workstation.py')
installer=importlib.util.module_from_spec(spec);spec.loader.exec_module(installer)

class WorkstationUnitTest(unittest.TestCase):
    def verify_with_docker_fixture(self, command, **kwargs):
        folder=Path(command[-1]).parent
        docker=folder/'docker.service';docker.write_text('[Service]\nType=oneshot\nExecStart=/bin/true\n')
        return subprocess.run([*command,str(docker)],**kwargs)
    @unittest.skipUnless(shutil.which('systemd-analyze'),'systemd parser required')
    def test_all_generated_units_parse_with_normal_and_space_containing_paths(self):
        with tempfile.TemporaryDirectory() as folder:
            for name in ['application','application with spaces']:
                with self.subTest(name=name):
                    root=Path(folder)/name;root.mkdir();state=root/'storage';state.mkdir()
                    config=installer.configuration(root,getpass.getuser(),'fixture',state)
                    installer.validate_units(config,run=self.verify_with_docker_fixture)
    @unittest.skipUnless(shutil.which('systemd-analyze'),'systemd parser required')
    def test_parser_reproduces_and_rejects_quoted_working_directory_regression(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);config=installer.configuration(root,getpass.getuser(),'fixture',root/'storage')
            config['unit']=config['unit'].replace('WorkingDirectory='+str(root),'WorkingDirectory="'+str(root)+'"')
            with self.assertRaisesRegex(RuntimeError,'WorkingDirectory=.*not absolute'):
                installer.validate_units(config,run=self.verify_with_docker_fixture)
    def test_failed_validation_precedes_all_installer_mutations(self):
        args=['installer','--app-root','/var/www/lightekmcg-site','--app-user','lightek','--app-name','lightekmcg-site','--domain','lightekmcg.com']
        with patch('sys.argv',args),patch.object(installer.os,'geteuid',return_value=0),patch.object(installer,'validate_units',side_effect=RuntimeError('Invalid fixture')),patch.object(installer.subprocess,'run') as command,patch.object(installer.Path,'write_text') as write,patch.object(installer.Path,'glob') as scan:
            with self.assertRaisesRegex(RuntimeError,'Invalid fixture'):installer.main()
            command.assert_not_called();write.assert_not_called();scan.assert_not_called()

if __name__=='__main__':unittest.main()
