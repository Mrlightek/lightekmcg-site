"""Compose two official character sources into an editable, lit first shot.

No source scripts are executed. Native meshes, armatures, constraints, drivers,
materials and textures are retained. Head gestures are ordinary editable keys.
"""
import bpy
import json
import math
import os
import sys
from mathutils import Vector

params = json.load(open(sys.argv[-1], encoding='utf-8'))
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.name = 'Rain and Snow · First scene'
for spec in params['sources']:
    before = set(bpy.data.objects)
    with bpy.data.libraries.load(spec['path'], link=False) as (available, target):
        target.scenes = available.scenes[:1]
    source = target.scenes[0]
    for collection in source.collection.children:
        scene.collection.children.link(collection)
    for obj in source.collection.objects:
        scene.collection.objects.link(obj)
    imported = set(bpy.data.objects) - before
    for obj in list(imported):
        if obj.type in ('CAMERA', 'LIGHT'):
            imported.discard(obj)
            bpy.data.objects.remove(obj, do_unlink=True)
    root = bpy.data.objects.new(spec['name'], None)
    scene.collection.objects.link(root)
    for obj in imported:
        if obj.parent not in imported:
            world = obj.matrix_world.copy()
            obj.parent = root
            obj.matrix_world = world
    root.location.x = spec['x']
    rig = next(o for o in imported if o.type == 'ARMATURE' and o.name.startswith('RIG-'))
    if rig.animation_data:
        rig.animation_data.action = None  # Preserve the rig drivers and constraints.
    bone = rig.pose.bones.get('FK-Head')
    if bone:
        bone.rotation_mode = 'XYZ'
        base = bone.rotation_euler.copy()
        for frame, tilt in [(1, 0), (12, .12), (24, -.1), (36, .06), (48, 0)]:
            bone.rotation_euler = base
            bone.rotation_euler.z += tilt * (1 if spec['x'] < 0 else -1)
            bone.keyframe_insert(data_path='rotation_euler', frame=frame)
    # Appended data normally has absolute image paths. Resolve any relative
    # textures while the downloaded archive's source tree is still present.
    for image in bpy.data.images:
        if image.filepath and not image.packed_file:
            path = bpy.path.abspath(image.filepath, library=image.library)
            if not os.path.exists(path):
                candidate = os.path.join(os.path.dirname(spec['path']), image.filepath.removeprefix('//'))
                if os.path.exists(candidate):
                    image.filepath = candidate
bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -.015))
floor = bpy.context.object
floor.name = 'Studio floor'
material = bpy.data.materials.new('Warm charcoal')
material.diffuse_color = (.045, .06, .08, 1)
floor.data.materials.append(material)
for name, position, energy, size in [('Key', (2, -4, 6), 1100, 5), ('Fill', (-4, -2, 3), 700, 4), ('Rim', (0, 3, 5), 1400, 3)]:
    data = bpy.data.lights.new(name, 'AREA')
    data.energy, data.size = energy, size
    light = bpy.data.objects.new(name, data)
    scene.collection.objects.link(light)
    light.location = position
    light.rotation_euler = (Vector((0, 0, 1.2)) - light.location).to_track_quat('-Z', 'Y').to_euler()
camera = bpy.data.objects.new('Two-shot camera', bpy.data.cameras.new('Two-shot lens'))
scene.collection.objects.link(camera)
camera.location = (3, -7, 2.7)
camera.rotation_euler = (Vector((0, 0, 1.15)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
camera.data.lens = 55
scene.camera = camera
scene.world = bpy.data.worlds.new('Studio ambience')
scene.world.color = (.08, .08, .08)
scene.render.engine = 'CYCLES'
scene.cycles.samples = 8
scene.cycles.use_denoising = False
scene.render.use_simplify = True
scene.render.simplify_subdivision_render = 1
scene.cycles.texture_limit_render = '1024'
scene.render.resolution_x, scene.render.resolution_y = 640, 360
scene.render.resolution_percentage = 100
scene.render.fps = 24
scene.frame_start, scene.frame_end = 1, 48
scene.frame_set(1)
credits = bpy.data.texts.new('Source credits')
credits.write('Rain Rig (CC) Blender Foundation | studio.blender.org\nSnow Rig (CC) Blender Foundation | studio.blender.org\nCC-BY 4.0 https://creativecommons.org/licenses/by/4.0/\n')
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=params['output'], compress=True)
if bpy.data.libraries:
    bpy.ops.file.make_paths_relative()
    bpy.ops.file.pack_libraries()
    bpy.ops.wm.save_as_mainfile(filepath=params['output'], compress=True)
