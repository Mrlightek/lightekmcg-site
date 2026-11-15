import importlib.util
import unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('rehearsal',Path(__file__).resolve().parents[2]/'blender/rehearsal.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class RehearsalPathsTest(unittest.TestCase):
    def test_route_goes_around_a_wall_and_each_segment_stays_outside_it(self):
        blocked=lambda x,y:1<=x<=2 and -1<=y<=1
        path=module.route([0,0],[4,0],blocked)
        self.assertIsNotNone(path)
        self.assertEqual([0.0,0.0],path[0]);self.assertEqual([4.0,0.0],path[-1])
        self.assertTrue(any(abs(y)>1 for x,y in path))
        for first,last in zip(path,path[1:]):
            for step in range(21):
                x=first[0]+(last[0]-first[0])*step/20;y=first[1]+(last[1]-first[1])*step/20
                self.assertFalse(blocked(x,y))
    def test_no_route_and_bounded_search_return_a_real_failure(self):
        self.assertIsNone(module.route([0,0],[4,0],lambda x,y:True))
        self.assertIsNone(module.route([0,0],[4,0],lambda x,y:False,limit=1))
    def test_intersecting_start_moves_to_a_nearby_clear_grid_position(self):
        blocked=lambda x,y:abs(x)<1 and abs(y)<1
        path=module.route([0,0],[3,0],blocked)
        self.assertIsNotNone(path);self.assertFalse(blocked(*path[0]))
if __name__=='__main__':unittest.main()
