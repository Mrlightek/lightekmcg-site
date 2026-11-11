"""Create an original, editable toon performer with face controls and pose bones."""
import bpy
import json
import math
import sys
from mathutils import Vector

params_path, output = sys.argv[sys.argv.index('--') + 1:]
with open(params_path, encoding='utf-8') as handle:
    params = json.load(handle)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.name = 'Lightek Performer'


def material(name, hex_color, roughness=0.5):
    color = tuple(int(hex_color[i:i+2], 16)/255 for i in (1, 3, 5)) + (1,)
    m = bpy.data.materials.new(name); m.diffuse_color = color; m.use_nodes = True
    node = m.node_tree.nodes.get('Principled BSDF')
    node.inputs['Base Color'].default_value = color
    node.inputs['Roughness'].default_value = roughness
    return m


skin = material('Skin', params.get('skin', '#925e43'))
wardrobe = material('Jacket', params.get('wardrobe', '#64388b'))
hair = material('Hair', params.get('hair', '#211916'))
gold = material('Lightek gold', '#d6a94a', 0.25)
white = material('Eye whites', '#f6f0de')
black = material('Mouth and pupils', '#170e12')
iris = material('Iris', '#553622')
trousers = material('Trousers', '#19212f')


def sphere(name, location, scale, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=20, location=location)
    obj = bpy.context.object; obj.name = name
    obj.scale = scale; bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    for face in obj.data.polygons: face.use_smooth = True
    return obj


body = sphere('Jacket body', (0, 0, 0.98), (0.40, 0.24, 0.52), wardrobe)
sphere('Shirt', (0, -0.21, 1.12), (0.22, 0.045, 0.30), black)
sphere('Neck', (0, 0, 1.49), (0.14, 0.14, 0.20), skin)
head = sphere('Head', (0, 0, 1.88), (0.34, 0.28, 0.42), skin)
head_parts = [head]
head_parts += [sphere('Ear L', (-0.34, 0, 1.86), (0.065, 0.06, 0.12), skin), sphere('Ear R', (0.34, 0, 1.86), (0.065, 0.06, 0.12), skin)]
head_parts += [sphere('Nose', (0, -0.285, 1.88), (0.065, 0.075, 0.10), skin)]
head_parts += [sphere('Hair cap', (0, 0.035, 2.17), (0.33, 0.26, 0.18), hair)]
for i in range(7):
    head_parts.append(sphere('Hair curl', ((i-3)*0.085, -0.10, 2.22+0.03*math.sin(i)), (0.065, 0.13, 0.065), hair))

# Joined eye parts share a blink shape without losing their individual materials.
eye_parts = []
for x in (-0.135, 0.135):
    eye_parts += [sphere('Eye', (x, -0.251, 1.99), (0.09, 0.055, 0.07), white), sphere('Iris', (x, -0.301, 1.99), (0.047, 0.017, 0.049), iris), sphere('Pupil', (x, -0.317, 1.99), (0.025, 0.008, 0.032), black), sphere('Catchlight', (x-0.011, -0.325, 2.007), (0.010, 0.005, 0.012), white)]
bpy.ops.object.select_all(action='DESELECT')
for obj in eye_parts: obj.select_set(True)
bpy.context.view_layer.objects.active = eye_parts[0]; bpy.ops.object.join()
eyes = bpy.context.object; eyes.name = 'FaceEyes'; eyes.shape_key_add(name='Basis')
blink = eyes.shape_key_add(name='blink')
for point in blink.data: point.co.z *= 0.05
head_parts.append(eyes)

brows = []
for x in (-0.135, 0.135): brows.append(sphere('Brow', (x, -0.26, 2.095), (0.105, 0.022, 0.022), hair))
bpy.ops.object.select_all(action='DESELECT')
for obj in brows: obj.select_set(True)
bpy.context.view_layer.objects.active = brows[0]; bpy.ops.object.join()
brow = bpy.context.object; brow.name = 'FaceBrows'; brow.shape_key_add(name='Basis')
raised = brow.shape_key_add(name='brow_raise')
for point in raised.data: point.co.z += 0.045
head_parts.append(brow)

# A deformable mouth mesh, rather than a text or texture approximation.
verts = [(0, -0.274, 1.72)]
for i in range(32):
    angle = i*math.tau/32
    verts.append((0.125*math.cos(angle), -0.274, 1.72+0.012*math.sin(angle)))
faces = [(0, 1+i, 1+(i+1)%32) for i in range(32)]
mesh = bpy.data.meshes.new('Facial mouth'); mesh.from_pydata(verts, [], faces); mesh.materials.append(black)
mouth = bpy.data.objects.new('FaceMouth', mesh); scene.collection.objects.link(mouth)
mouth.shape_key_add(name='Basis')
for name in ('jaw_open', 'smile', 'mouth_wide', 'mouth_round'):
    key = mouth.shape_key_add(name=name)
    for point in key.data:
        x, y, z = point.co
        if name == 'jaw_open': point.co.z = 1.72+(z-1.72)*7
        if name == 'smile': point.co.z += 0.045*(abs(x)/0.125)**2
        if name == 'mouth_wide': point.co.x *= 1.4
        if name == 'mouth_round': point.co.x *= 0.55; point.co.z = 1.72+(z-1.72)*4
head_parts.append(mouth)

arm_parts = {}
for side, x in [('L', -0.43), ('R', 0.43)]:
    arm_parts[side] = [sphere('Sleeve '+side, (x, 0, 1.05), (0.12, 0.14, 0.36), wardrobe), sphere('Hand '+side, (x, -0.01, 0.72), (0.10, 0.09, 0.12), skin)]
for x in (-0.17, 0.17):
    sphere('Trouser leg', (x, 0, 0.43), (0.15, 0.16, 0.43), trousers)
    sphere('Boot', (x, -0.09, 0.08), (0.17, 0.24, 0.10), black)
sphere('Jacket pin', (0.24, -0.221, 1.28), (0.035, 0.025, 0.035), gold)

rig = bpy.data.objects.new('PerformerRig', bpy.data.armatures.new('Performer bones')); scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig; rig.select_set(True); bpy.ops.object.mode_set(mode='EDIT')
for name, a, b in [('Head', (0, 0, 1.48), (0, 0, 2.2)), ('Arm.L', (-0.35, 0, 1.35), (-0.43, 0, 0.72)), ('Arm.R', (0.35, 0, 1.35), (0.43, 0, 0.72))]:
    bone = rig.data.edit_bones.new(name); bone.head = a; bone.tail = b
bpy.ops.object.mode_set(mode='OBJECT')
for bone_name, parts in [('Head', head_parts), ('Arm.L', arm_parts['L']), ('Arm.R', arm_parts['R'])]:
    for obj in parts:
        world = obj.matrix_world.copy(); obj.parent = rig; obj.parent_type = 'BONE'; obj.parent_bone = bone_name
        bpy.context.view_layer.update(); obj.matrix_world = world

camera = bpy.data.objects.new('Portrait camera', bpy.data.cameras.new('Portrait lens')); scene.collection.objects.link(camera)
camera.location = (0, -5, 1.7); camera.rotation_euler = (Vector((0, 0, 1.5))-camera.location).to_track_quat('-Z', 'Y').to_euler(); camera.data.lens = 60; scene.camera = camera
for name, loc, power, size in [('Key', (3, -4, 5), 800, 4), ('Fill', (-3, -2, 3), 400, 4), ('Rim', (1, 2, 4), 900, 3)]:
    light = bpy.data.objects.new(name, bpy.data.lights.new(name, 'AREA')); scene.collection.objects.link(light); light.location = loc; light.data.energy = power; light.data.shape = 'DISK'; light.data.size = size; light.rotation_euler = (Vector((0, 0, 1.3))-light.location).to_track_quat('-Z', 'Y').to_euler()
scene.world = bpy.data.worlds.new('Studio world'); scene.world.color = (0.07, 0.08, 0.12)
scene.render.engine = 'CYCLES'; scene.cycles.samples = 8; scene.render.resolution_x = 512; scene.render.resolution_y = 512; scene.render.resolution_percentage = 100
bpy.ops.wm.save_as_mainfile(filepath=output)
