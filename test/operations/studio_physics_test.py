"""Behavioral checks against the CPU solver, including failed grips."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('grasp',ROOT/'blender/physics/grasp_v1.py')
grasp=importlib.util.module_from_spec(spec);spec.loader.exec_module(grasp)

class PhysicalGraspTest(unittest.TestCase):
    def setUp(self):self.profile=json.loads(grasp.PROFILE.read_text())
    def test_contact_supports_load_without_weld_or_parent(self):
        result=grasp.simulate(self.profile);report=result['report']
        self.assertNotIn('<equality',result['model_xml'])
        self.assertIn('<freejoint/>',result['model_xml'])
        self.assertGreater(report['lift_m'],.13)
        self.assertLess(report['max_penetration_m'],.002)
        self.assertLessEqual(report['max_finger_torque_nm'],.35)
        self.assertGreater(report['max_load_contacts'],4)
        self.assertAlmostEqual(report['settled_height_m'],.145,delta=.002)
        self.assertEqual(len(result['frames']),96)
        self.assertFalse(report['whole_body_dynamics'])
    def test_insufficient_finger_strength_cannot_carry_same_load(self):
        weak=copy.deepcopy(self.profile);weak['finger_torque_limit_nm']=.001
        result=grasp.simulate(weak)
        self.assertLess(result['report']['lift_m'],.015)
        self.assertLessEqual(result['report']['max_finger_torque_nm'],.00100001)
    def test_mass_changes_grip_response_and_body_mass_changes_inertia(self):
        light=grasp.simulate(self.profile)
        heavy=copy.deepcopy(self.profile);heavy['prop_mass_kg']=3
        result=grasp.simulate(heavy)
        self.assertGreater(light['report']['lift_m']-result['report']['lift_m'],.005)
        larger=copy.deepcopy(self.profile);larger['body_mass_kg']=100
        xml,_=grasp.model(larger)
        self.assertNotEqual(xml,light['model_xml'])
    def test_reproducible_fixed_step_simulation(self):
        a=grasp.simulate(self.profile);b=grasp.simulate(self.profile)
        self.assertEqual(a,b)

if __name__=='__main__':unittest.main()
