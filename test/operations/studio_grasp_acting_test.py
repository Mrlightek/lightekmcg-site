"""Verify living contact motion and load behavior, not just authored key counts."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('acting_grasp',ROOT/'blender/physics/grasp_v3.py')
grasp=importlib.util.module_from_spec(spec);spec.loader.exec_module(grasp)

class ActingContactTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):cls.result=grasp.simulate()
    def test_lift_keeps_contact_limits_and_supported_return(self):
        report=self.result['report']
        self.assertGreater(report['lift_m'],.13)
        self.assertLess(report['max_penetration_m'],.002)
        self.assertLessEqual(report['max_finger_torque_nm'],.35)
        self.assertAlmostEqual(report['settled_height_m'],.145,delta=.002)
        self.assertGreaterEqual(report['min_hold_contacts'],4)
        self.assertNotIn('<equality',self.result['model_xml'])
    def test_no_frozen_hold_and_actual_finger_adjustment(self):
        held=[f for f in self.result['frames'] if 3<=f['time_s']<4.5]
        self.assertTrue(all(np.linalg.norm(np.array(a['ball'])-b['ball'])>1e-5 for a,b in zip(held,held[1:])))
        self.assertGreater(self.result['report']['hold_load_travel_m'],.001)
        self.assertGreater(self.result['report']['hold_finger_adjustment_rad'],.005)
        self.assertGreater(max(f['ball'][2] for f in held)-min(f['ball'][2] for f in held),.002)
    def test_weak_grip_still_cannot_fake_lift(self):
        p=json.loads(grasp.PROFILE.read_text());p['finger_torque_limit_nm']=.001
        self.assertLess(grasp.simulate(p)['report']['lift_m'],.015)
    def test_prop_is_supported_before_fingers_open_and_hand_disengages(self):
        frames=self.result['frames']
        touch=next(f for f in frames if f['time_s']>=5.5)
        self.assertLess(touch['ball'][2]-.145,.002)
        end=frames[-1]
        self.assertGreater(np.linalg.norm(np.array(end['hand'])-end['ball']),.30)
        self.assertLess(max(abs(v) for v in end['motor_targets_rad']),1e-8)
    def test_reproducible_performance(self):
        self.assertEqual(self.result,grasp.simulate())

if __name__=='__main__':unittest.main()
