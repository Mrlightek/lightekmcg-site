"""The CI Blender wrapper isolates embedded Python without changing arguments."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
ROOT=Path(__file__).resolve().parents[2]

class BlenderEnvironmentTest(unittest.TestCase):
    def invoke(self, status=0):
        with tempfile.TemporaryDirectory() as directory:
            binary=Path(directory)/'blender'
            binary.write_text('''#!/bin/sh
[ "${LD_LIBRARY_PATH+x}" != x ] || exit 80
[ "${PYTHONHOME+x}" != x ] || exit 81
[ "${PYTHONPATH+x}" != x ] || exit 82
[ "$STUDIO_TEST_KEEP" = keep ] || exit 83
printf '%s\\n' "$@"
exit '''+str(status)+'\n')
            binary.chmod(0o755)
            environment=dict(os.environ,LD_LIBRARY_PATH='/nonexistent/toolchain',PYTHONHOME='/nonexistent/python',PYTHONPATH='/nonexistent/modules',STUDIO_TEST_KEEP='keep',STUDIO_SYSTEM_BLENDER_BIN=str(binary))
            return subprocess.run(['bash',str(ROOT/'lib/scripts/ci_blender.sh'),'--background','--python-expr','import bpy, numpy'],env=environment,text=True,capture_output=True)
    def test_embedded_python_is_clean_and_arguments_are_preserved(self):
        result=self.invoke()
        self.assertEqual(0,result.returncode,result.stderr)
        self.assertEqual('--background\n--python-expr\nimport bpy, numpy\n',result.stdout)
    def test_engine_failure_is_not_hidden(self):
        self.assertEqual(17,self.invoke(status=17).returncode)

if __name__=='__main__':unittest.main()
