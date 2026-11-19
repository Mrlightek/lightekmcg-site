"""Measure motion in encoded pixels, independently from the browser preview."""
import copy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
class LayeredRendererTest(unittest.TestCase):
    def spec(self):
        layers=[]
        for index,(x,y,depth) in enumerate([(50,25,.2),(110,65,.9)]):
            layers.append(dict(source=f'source-{index}.svg',source_kind='svg',width=20,height=20,rotation=0,opacity=1,depth=depth,x=x,y=y))
        return dict(canvas=dict(width=160,height=90,fps=4,duration=1),camera=dict(x=.3,y=0),layers=layers)
    def render(self,spec,expected_error=None):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            for index,color in enumerate(['red','lime']):
                (root/f'source-{index}.svg').write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><rect width="20" height="20" fill="{color}"/></svg>')
            (root/'render.json').write_text(json.dumps(spec))
            result=subprocess.run(['python3',str(ROOT/'lib/scripts/studio_layered_renderer.py'),str(root/'render.json'),str(root)],capture_output=True)
            if expected_error:
                self.assertNotEqual(result.returncode,0)
                self.assertIn(expected_error,result.stderr.decode())
                self.assertFalse((root/'scene.mp4').exists())
                return
            self.assertEqual(result.returncode,0,result.stderr.decode())
            data=subprocess.check_output(['ffmpeg','-v','error','-i',str(root/'scene.mp4'),'-f','rawvideo','-pix_fmt','rgb24','-'])
            size=160*90*3
            self.assertEqual(json.loads((root/'metrics.json').read_text())['engine'],'lightek_2d')
            return [data[index:index+size] for index in range(0,len(data),size)]
    def center(self,frame,channel):
        xs=[(offset//3)%160 for offset in range(0,len(frame),3) if frame[offset+channel]>150 and all(frame[offset+other]<100 for other in range(3) if other!=channel)]
        self.assertTrue(xs)
        return sum(xs)/len(xs)
    def test_exported_parallax_moves_foreground_farther(self):
        frames=self.render(self.spec())
        far=self.center(frames[0],0)-self.center(frames[-1],0)
        near=self.center(frames[0],1)-self.center(frames[-1],1)
        self.assertGreater(far,3)
        self.assertGreater(near,far*3)
        self.assertEqual(len(frames),4)
        self.assertAlmostEqual(near,160*.3*.9*.75,delta=2)
    def test_loop_and_one_shot_asset_motion_work_with_a_stationary_camera(self):
        spec=self.spec();spec['camera']['x']=0;spec['canvas'].update(fps=8,duration=2)
        spec['layers'][0]['motions']=[dict(duration=1,loop=True,keyframes=[dict(t=0,x=0,y=0),dict(t=.5,x=20,y=0),dict(t=1,x=0,y=0)])]
        spec['layers'][1]['motions']=[dict(duration=2,loop=False,keyframes=[dict(t=0,x=0,y=0),dict(t=1,x=-20,y=0)])]
        frames=self.render(spec)
        self.assertEqual(len(frames),16)
        red=[self.center(frames[i],0) for i in [0,4,8,12]]
        self.assertAlmostEqual(red[1]-red[0],20,delta=2)
        self.assertAlmostEqual(red[2],red[0],delta=2)
        self.assertAlmostEqual(red[3],red[1],delta=2)
        self.assertAlmostEqual(self.center(frames[0],1)-self.center(frames[-1],1),18.75,delta=2)
    def test_render_rejects_expressions_unordered_keyframes_and_discontinuous_loops(self):
        track=dict(duration=1,loop=False,keyframes=[dict(t=0,x=0,y=0),dict(t=1,x=10,y=0)])
        invalid=copy.deepcopy(track);invalid['keyframes'][0]['x']='movie=secret'
        spec=self.spec();spec['layers'][0]['motions']=[invalid]
        self.render(spec,'Invalid motion values')
        invalid=copy.deepcopy(track);invalid['keyframes'][1]['t']=0
        spec['layers'][0]['motions']=[invalid];self.render(spec,'Invalid keyframe order')
        invalid=copy.deepcopy(track);invalid['loop']=True
        spec['layers'][0]['motions']=[invalid];self.render(spec,'Discontinuous motion loop')

if __name__=='__main__': unittest.main()
