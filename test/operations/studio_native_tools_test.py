"""Real Blender proofs for each native authoring tool family."""
import os
from pathlib import Path
import subprocess
import sys
import unittest
ROOT = Path(__file__).resolve().parents[2]


def proof():
    import bpy
    sys.path.insert(0, str(ROOT / 'blender'))
    import authoring
    def cube():
        bpy.ops.mesh.primitive_cube_add()
        return bpy.context.object
    for kind, extra in [
        ('mesh_translate', {'indices': [0], 'delta': [1, 0, 0]}),
        ('mesh_subdivide', {'indices': [0], 'cuts': 2}),
        ('mesh_inset', {'indices': [0], 'amount': .1}),
        ('mesh_bevel', {'indices': [0], 'amount': .1, 'segments': 2}),
        ('mesh_delete', {'indices': [0]}),
        ('mesh_merge', {'indices': [], 'amount': .01}),
        ('mesh_smooth', {'indices': [0], 'amount': .5, 'iterations': 2}),
    ]:
        obj = cube()
        if kind == 'mesh_merge': obj.data.vertices[0].co = obj.data.vertices[1].co
        authoring.apply(obj, [{'kind': kind, **extra}])
        if kind in ('mesh_subdivide', 'mesh_inset', 'mesh_bevel'): assert len(obj.data.vertices) > 8, kind
        if kind == 'mesh_delete': assert len(obj.data.polygons) == 5
        if kind == 'mesh_merge': assert len(obj.data.vertices) == 7
    obj = cube()
    authoring.apply(obj, [{'kind': 'sculpt', 'center': [1,1,1], 'path': [[-1,1,1]], 'delta': [0,0,.1], 'radius': .5}])
    assert max(v.co.z for v in obj.data.vertices) > 1
    for kind, props in [('SUBSURF', {'levels':1}), ('MIRROR', {'use_clip':True}), ('SOLIDIFY', {'thickness':.1}), ('DECIMATE', {'ratio':.5})]:
        authoring.apply(obj, [{'kind':'modifier','name':'Test '+kind,'type':kind,'properties':props}])
        assert obj.modifiers['Test '+kind].type == kind
    obj = cube();obj.shape_key_add(name='Basis');obj.shape_key_add(name='Smile')
    authoring.apply(obj, [{'kind':'shape_key','name':'Smile','value':.6,'frame':2}])
    assert abs(obj.data.shape_keys.key_blocks['Smile'].value-.6) < .00001
    assert obj.data.shape_keys.animation_data.action
    authoring.apply(obj, [
        {'kind':'node_add','scope':'geometry','modifier':'Studio Geometry','name':'New Cube','type':'GeometryNodeMeshCube'},
        {'kind':'node_link','scope':'geometry','modifier':'Studio Geometry','from':'New Cube','output':0,'to':'Group Output','input':0},
    ])
    assert obj.modifiers['Studio Geometry'].node_group.nodes['New Cube']
    authoring.apply(obj, [
        {'kind':'node_add','scope':'compositor','name':'Studio Glow','type':'CompositorNodeGlare'},
        {'kind':'node_link','scope':'compositor','from':'Render Layers','output':0,'to':'Studio Glow','input':0},
        {'kind':'node_link','scope':'compositor','from':'Studio Glow','output':0,'to':'Composite','input':0},
    ])
    links={(link.from_node.name,link.to_node.name) for link in bpy.context.scene.node_tree.links}
    assert ('Render Layers','Studio Glow') in links
    assert ('Studio Glow','Composite') in links
    assert bpy.context.scene.node_tree.nodes['Composite'].inputs[0].links[0].from_node.name=='Studio Glow'
    inventory = authoring.inventory(obj)
    assert inventory['shape_keys'][1]['name'] == 'Smile'
    assert inventory['graphs'][0]['scope'] == 'geometry'
    try:
        authoring.apply(obj,[{'kind':'mesh_translate','indices':[-1],'delta':[0,0,1]}])
        raise AssertionError('Negative selection accepted')
    except ValueError:
        pass
    # The shared builder also powers spatial streaming. Merge integration must
    # retain journal edits, native picking identity and spatial anchors together.
    import runner
    created = runner.stage_manifest({'scene': {'settings': {'render_engine':'CYCLES','samples':1,'resolution_x':64,'resolution_y':64}, 'objects': [
        {'id': 71, 'type':'cube', 'name':'Merged stage prop', 'definition': {
            'staging_anchors':True, 'authoring_commands':[{'kind':'mesh_subdivide','indices':[],'cuts':1}]
        }}
    ]}})
    staged=created['71']
    assert len(staged.data.vertices)>8
    assert staged['lightek_object_name']==staged.name
    assert {child['lightek_anchor_kind'] for child in staged.children}=={'rig','collision'}
    print('NATIVE_TOOLS_PASS topology sculpt_stroke modifiers shape_keys geometry_graph compositor_graph selection_validation')


class NativeToolsTest(unittest.TestCase):
    @unittest.skipUnless(os.environ.get('BLENDER_BIN'), 'Set BLENDER_BIN for native engine proofs')
    def test_real_blender_native_tools(self):
        result = subprocess.run([os.environ['BLENDER_BIN'], '--background', '--factory-startup', '--disable-autoexec', '--python-exit-code','1','--python',str(Path(__file__).resolve()),'--','--blender-proof'], text=True, capture_output=True, timeout=90)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('NATIVE_TOOLS_PASS', result.stdout)


if __name__ == '__main__':
    if '--blender-proof' in sys.argv: proof()
    else: unittest.main()
