"""Exercise the character builder with a native armature, linked shader, and render."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

FIXTURE = """
import bpy
import sys
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.context.scene.name = 'Character source'
bpy.ops.object.armature_add()
rig = bpy.context.object
rig.name = 'Custom armature'
rig.location.x = .1
rig.keyframe_insert(data_path='location', index=0, frame=1)
rig.location.x = .2
rig.keyframe_insert(data_path='location', index=0, frame=12)
constraint = rig.pose.bones[0].constraints.new('LIMIT_ROTATION')
constraint.name = 'Original control'
bpy.ops.mesh.primitive_uv_sphere_add(radius=.5, location=(0, 0, .8))
mesh = bpy.context.object
mesh.name = 'Character mesh'
mesh.vertex_groups.new(name=rig.data.bones[0].name).add(list(range(len(mesh.data.vertices))), 1, 'REPLACE')
mesh.modifiers.new('Skin', 'ARMATURE').object = rig
material = bpy.data.materials.new('Original colors')
material.use_nodes = True
node = material.node_tree.nodes.new('ShaderNodeRGB')
node.outputs[0].default_value = (.6, .4, .2, 1)
material.node_tree.links.new(node.outputs[0], material.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
mesh.data.materials.append(material)
bpy.ops.wm.save_as_mainfile(filepath=sys.argv[-1])
"""

VERIFY = """
import bpy
import math
import sys
rig = bpy.data.objects['Custom armature']
mesh = bpy.data.objects['Character mesh']
root = bpy.data.objects['Custom hero']
assert len(rig.pose.bones) == 1
assert rig.pose.bones[0].constraints.get('Original control')
assert rig.animation_data.action
assert mesh.modifiers[0].object == rig
assert mesh.parent == root and rig.parent == root
assert all(abs(value - 1.2) < .0001 for value in root.scale)
assert abs(root.rotation_euler.z - math.radians(30)) < .0001
material = mesh.data.materials[0]
base = material.node_tree.nodes.get('Principled BSDF').inputs['Base Color']
mix = base.links[0].from_node
assert mix.blend_type == 'MULTIPLY' and mix.inputs[1].links[0].from_node.type == 'RGB'
scene = bpy.context.scene
assert scene.camera and any(obj.type == 'LIGHT' for obj in scene.objects)
scene.render.resolution_x = 96
scene.render.resolution_y = 64
scene.cycles.samples = 2
scene.render.threads_mode = 'FIXED'
scene.render.threads = 2
scene.render.filepath = sys.argv[-1]
bpy.ops.render.render(write_still=True)
"""


class RiggedCharacterTest(unittest.TestCase):
    def blender(self, *args):
        command = [os.environ.get('BLENDER_BIN', 'blender'), '--background', *args]
        result = subprocess.run(command, capture_output=True, text=True, timeout=90, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_copies_edits_and_renders_a_native_character(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture, verify = root / 'fixture.py', root / 'verify.py'
            fixture.write_text(FIXTURE)
            verify.write_text(VERIFY)
            original, output, frame = root / 'source.blend', root / 'variant.blend', root / 'preview.png'
            flags = ('--disable-autoexec', '--python-exit-code', '1')
            self.blender('--factory-startup', *flags, '--python', str(fixture), '--', str(original))
            original_sha = hashlib.sha256(original.read_bytes()).digest()
            params = root / 'params.json'
            params.write_text(json.dumps({
                'sources': [{'path': str(original), 'name': 'Fixture', 'x': 0}],
                'character': {'rig': 'library', 'scene': 'Character source', 'height': 1.2, 'facing': 30, 'tint': '#f58048'},
                'name': 'Custom hero', 'output': str(output)
            }))
            self.blender('--factory-startup', *flags, '--python', str(ROOT / 'blender/starter_cast.py'), '--', str(params))
            self.blender(str(output), *flags, '--python', str(verify), '--', str(frame))
            self.assertEqual(hashlib.sha256(original.read_bytes()).digest(), original_sha)
            self.assertEqual(frame.read_bytes()[:8], b'\x89PNG\r\n\x1a\n')


if __name__ == '__main__':
    unittest.main()
