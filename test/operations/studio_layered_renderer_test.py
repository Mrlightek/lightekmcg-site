"""Verify exported pixels, including independent foreground/background motion."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
class LayeredRendererTest(unittest.TestCase):
    def test_exported_parallax_moves_foreground_farther(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            layers=[]
            for index,(color,x,y,depth) in enumerate([('red',50,25,.2),('lime',110,65,.9)]):
                source=f'source-{index}.svg'
                (root/source).write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20"><rect width="20" height="20" fill="{color}"/></svg>')
                layers.append(dict(source=source,source_kind='svg',width=20,height=20,rotation=0,opacity=1,depth=depth,x=x,y=y))
            spec=dict(canvas=dict(width=160,height=90,fps=4,duration=1),camera=dict(x=.3,y=0),layers=layers)
            (root/'render.json').write_text(json.dumps(spec))
            subprocess.run(['python3',str(ROOT/'lib/scripts/studio_layered_renderer.py'),str(root/'render.json'),str(root)],check=True,capture_output=True)
            data=subprocess.check_output(['ffmpeg','-v','error','-i',str(root/'scene.mp4'),'-f','rawvideo','-pix_fmt','rgb24','-'])
            size=160*90*3
            def center(frame,channel):
                xs=[(offset//3)%160 for offset in range(0,len(frame),3) if frame[offset+channel]>150 and all(frame[offset+other]<100 for other in range(3) if other!=channel)]
                self.assertTrue(xs)
                return sum(xs)/len(xs)
            first,last=data[:size],data[-size:]
            far=center(first,0)-center(last,0)
            near=center(first,1)-center(last,1)
            self.assertGreater(far,3)
            self.assertGreater(near,far*3)
            self.assertEqual(len(data)//size,4)
            self.assertAlmostEqual(near,160*.3*.9*.75,delta=2)
            self.assertEqual(json.loads((root/'metrics.json').read_text())['engine'],'lightek_2d')

if __name__=='__main__': unittest.main()
