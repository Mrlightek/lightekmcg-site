import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from lib.scripts.studio_worker_limits import BlenderCapacityError, MIB, blender_memory_limit, cpu_limit
ROOT=Path(__file__).resolve().parents[2]

class CpuLimitsTest(unittest.TestCase):
    def test_default_budget_fits_single_cpu_daemon_and_keeps_two_cpu_ceiling(self):
        with patch.dict(os.environ,{},clear=True):
            for count,expected in [('1','1'),('2','2'),('8','2')]:
                with self.subTest(count=count),patch('subprocess.check_output',return_value=count) as inspect:
                    self.assertEqual(expected,cpu_limit())
                    self.assertEqual(['docker','info','--format','{{.NCPU}}'],inspect.call_args.args[0])
    def test_fractional_and_explicit_budgets_are_preserved_or_clamped(self):
        with patch('subprocess.check_output',return_value='1'):
            self.assertEqual('0.5',cpu_limit('0.5'))
            self.assertEqual('1',cpu_limit('4'))
            with patch.dict(os.environ,STUDIO_WORKER_CPUS='0.25'):self.assertEqual('0.25',cpu_limit())
    def test_invalid_budgets_or_daemon_capacity_fail_before_worker_launch(self):
        for value in ['nan','inf','0','-1','bad']:
            with self.subTest(value=value),self.assertRaises(ValueError):cpu_limit(value)
        for value in ['0','-1','unknown']:
            with patch('subprocess.check_output',return_value=value),self.assertRaises(ValueError):cpu_limit('2')
    def test_spatial_container_uses_the_same_cpu_policy(self):
        from services.spatial.launcher import container_launcher
        with patch('subprocess.check_output',side_effect=[f'{4096 * MIB} true true','1']), \
             patch.object(Path,'read_text',return_value='MemAvailable: 3670016 kB\n'):
            command=container_launcher('fixture/image','background')(['blender','--background','--python','worker.py'],'/tmp/scene')
        self.assertEqual('1',command[command.index('--cpus')+1])
        self.assertEqual('none',command[command.index('--network')+1])
        self.assertEqual('2816m',command[command.index('--memory')+1])
        self.assertEqual('2816m',command[command.index('--memory-swap')+1])
        self.assertEqual('lightek-blender-slot',command[command.index('--name')+1])
    def test_real_cli_queries_daemon_and_preserves_fractional_budget(self):
        with tempfile.TemporaryDirectory() as temp:
            docker=Path(temp)/'docker';docker.write_text('#!/bin/sh\n[ "$*" = "info --format {{.NCPU}}" ] || exit 3\nprintf "1\\n"\n');docker.chmod(0o755)
            env=dict(os.environ,PATH=temp+os.pathsep+os.environ['PATH'],STUDIO_WORKER_CPUS='0.5')
            result=subprocess.run(['python3',str(ROOT/'lib/scripts/studio_worker_limits.py')],env=env,text=True,capture_output=True)
            self.assertEqual(0,result.returncode,result.stderr);self.assertEqual('0.5\n',result.stdout)

class BlenderMemoryTest(unittest.TestCase):
    def budget(self, total, available, request="4g", capabilities="true true"):
        with patch("subprocess.check_output", return_value=f"{total * MIB} {capabilities}"):
            with patch.object(Path, "read_text", return_value=f"MemAvailable: {available * 1024} kB\n"):
                return blender_memory_limit(request)

    def test_production_server_from_the_incident_cannot_admit_a_standard_render(self):
        with self.assertRaises(BlenderCapacityError):
            self.budget(1968, 734)

    def test_reserves_physical_memory_and_respects_live_availability(self):
        self.assertEqual("1792m", self.budget(3072, 2800))
        self.assertEqual("1088m", self.budget(8192, 1600))
        self.assertEqual("1024m", self.budget(8192, 6000, "1g"))

    def test_can_run_a_small_request_when_it_fits_the_host_budget(self):
        self.assertEqual("512m", self.budget(1968, 1100, "512m"))

    def test_rejects_a_host_that_cannot_enforce_swap_limits(self):
        with self.assertRaises(BlenderCapacityError):
            self.budget(8192, 6000, capabilities="true false")

if __name__=='__main__':unittest.main()
