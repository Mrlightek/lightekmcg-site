import os
from pathlib import Path
import subprocess
import sys
import unittest
ROOT=Path(__file__).resolve().parents[2]


def proof():
    import bpy
    import hashlib
    import json
    import tempfile
    import zipfile
    with tempfile.TemporaryDirectory(prefix='native-studio-bridge-') as temp:
        work=Path(temp)/'work';work.mkdir();(work/'cache').mkdir();(work/'cache/effect.bin').write_bytes(b'CACHE-PROOF')
        cube=bpy.context.scene.objects['Cube']
        uv=cube.data.uv_layers.active or cube.data.uv_layers.new(name='Studio UV')
        uv.data[0].uv=(.25,.75)
        cube.keyframe_insert(data_path='location',frame=1);cube.location.x=2;cube.keyframe_insert(data_path='location',frame=10)
        curve=cube.animation_data.action.fcurves[0];curve.keyframe_points[0].interpolation='BEZIER'
        track=cube.animation_data.nla_tracks.new();track.name='Studio take';track.strips.new('Studio clip',1,cube.animation_data.action)
        target=bpy.data.objects.new('RigTarget',None);bpy.context.scene.collection.objects.link(target)
        constraint=cube.constraints.new('COPY_ROTATION');constraint.name='Studio constraint';constraint.target=target
        cloth=cube.modifiers.new('Studio cloth','CLOTH');cloth.settings.mass=.4
        image=bpy.data.images.new('Packed paint',width=4,height=4);image.pixels=[.2,.5,.8,1]*16;image.pack()
        material=cube.data.materials[0];material.use_nodes=True;texture=material.node_tree.nodes.new('ShaderNodeTexImage');texture.image=image
        material.node_tree.links.new(texture.outputs['Color'],material.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
        scene=bpy.context.scene;scene.use_nodes=True;glow=scene.node_tree.nodes.new('CompositorNodeGlare');glow.label='Studio glow'
        seq=scene.sequence_editor_create();seq.sequences.new_effect(name='Studio title layer',type='COLOR',channel=1,frame_start=1,frame_end=10)
        original=Path(temp)/'original.blend';bpy.ops.wm.save_as_mainfile(filepath=str(original),compress=True)
        original_bytes=original.read_bytes()
        os.environ['LIGHTEK_WORKSTATION_TEST_ROOT']=str(work);sys.path.insert(0,str(ROOT/'blender'));import workstation
        (work/'.studio-save-request.json').write_text(json.dumps({'nonce':'a'*16}))
        cube.location.z=3;workstation.save_session()
        receipt=json.loads((work/'.studio-save-receipt.json').read_text())
        assert receipt['nonce']=='a'*16
        assert receipt['sha256']==hashlib.sha256((work/'scene.blend').read_bytes()).hexdigest()
        assert receipt['bundle_sha256']==hashlib.sha256((work/'project.zip').read_bytes()).hexdigest()
        with zipfile.ZipFile(work/'project.zip') as package:
            assert 'scene.blend' in package.namelist();assert package.read('cache/effect.bin')==b'CACHE-PROOF'
            assert not any(name.startswith('.') for name in package.namelist())
        assert original.read_bytes()==original_bytes
        bpy.ops.wm.open_mainfile(filepath=str(work/'scene.blend'),load_ui=False,use_scripts=False)
        cube=bpy.data.objects['Cube'];assert abs(cube.data.uv_layers.active.data[0].uv.y-.75)<.001
        assert cube.constraints['Studio constraint'].target.name=='RigTarget'
        assert abs(cube.modifiers['Studio cloth'].settings.mass-.4)<.001
        assert cube.animation_data.nla_tracks[0].name=='Studio take'
        assert cube.animation_data.action.fcurves[0].keyframe_points[0].interpolation=='BEZIER'
        assert bpy.data.images['Packed paint'].packed_file
        assert any(node.label=='Studio glow' for node in bpy.context.scene.node_tree.nodes)
        assert bpy.context.scene.sequence_editor.sequences[0].name=='Studio title layer'
        print('WORKSTATION_BRIDGE_PASS native_uv constraint fcurve_nla simulation_settings packed_paint compositor sequencer resource_zip immutable_source')


class WorkstationBridgeTest(unittest.TestCase):
    @unittest.skipUnless(os.environ.get('BLENDER_BIN'),'Set BLENDER_BIN for native save bridge proof')
    def test_native_project_round_trip(self):
        result=subprocess.run([os.environ['BLENDER_BIN'],'--factory-startup','--background','--disable-autoexec','--python-exit-code','1','--python',str(Path(__file__).resolve()),'--','--bridge-proof'],text=True,capture_output=True,timeout=90)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr);self.assertIn('WORKSTATION_BRIDGE_PASS',result.stdout)

if __name__=='__main__':
    if '--bridge-proof' in sys.argv:proof()
    else:unittest.main()
