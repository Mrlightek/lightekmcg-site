import importlib.util
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('visemes',ROOT/'blender/visemes.py')
visemes=importlib.util.module_from_spec(spec);spec.loader.exec_module(visemes)
class VisemeTest(unittest.TestCase):
    def test_exact_shapes_replace_coarse_mapping_and_reset_at_end(self):
        curves=visemes.curves([{'start':0,'end':.5,'value':'D'},{'start':.5,'end':1,'value':'F'}],duration=1,start=2,fps=24,bindings=['jaw_open','mouth_round','viseme_d','viseme_f'])
        self.assertEqual(1,curves['viseme_d'][2]);self.assertEqual(0,curves['jaw_open'][2])
        self.assertEqual(1,curves['viseme_f'][2.5]);self.assertEqual(0,curves['viseme_d'][2.5])
        for control,points in curves.items(): self.assertEqual(0,points[3],control)
    def test_older_rigs_use_bound_coarse_channels_and_gaps_rest(self):
        result=visemes.curves([{'start':.25,'end':.5,'value':'D'},{'start':.75,'end':1,'value':'F'}],duration=1,start=0,fps=24,bindings=['jaw_open','mouth_round','smile'])
        self.assertEqual(0,result['jaw_open'][0]);self.assertEqual(1,result['jaw_open'][.25])
        self.assertEqual(0,result['jaw_open'][.5]);self.assertEqual(1,result['mouth_round'][.75])
        self.assertNotIn('smile',result)
    def test_fractional_duration_has_exact_end_reset(self):
        result=visemes.curves([{'start':0,'end':.31,'value':'D'}],duration=.31,start=.13,fps=24/1.001,bindings=['jaw_open'])
        self.assertEqual(0,result['jaw_open'][.44]);self.assertLessEqual(len(result['jaw_open']),11)
if __name__=='__main__': unittest.main()
