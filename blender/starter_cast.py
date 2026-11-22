"""Build an editable, lit first shot from native Blender characters or meshes.

No source scripts are executed. Native meshes, armatures, constraints, drivers,
materials and textures are retained. Head gestures are ordinary editable keys.
"""
import bpy
import json
import math
import os
import sys
from mathutils import Vector

def tint_material(materials, hex_color):
    rgb = [int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    linear = tuple(channel / 12.92 if channel < .04045 else
                   ((channel + .055) / 1.055) ** 2.4 for channel in rgb)
    multiplier = tuple(.5 + channel * .5 for channel in linear)
    for material in materials:
        if material.use_nodes and material.node_tree:
            tree = material.node_tree
            for surface in [node for node in tree.nodes if node.type == 'BSDF_PRINCIPLED']:
                base = surface.inputs['Base Color']
                if base.is_linked:
                    upstream = base.links[0].from_socket
                    mix = tree.nodes.new('ShaderNodeMixRGB')
                    mix.blend_type = 'MULTIPLY'
                    mix.inputs[0].default_value = 1
                    mix.inputs[2].default_value = (*multiplier, 1)
                    tree.links.new(upstream, mix.inputs[1])
                    tree.links.new(mix.outputs[0], base)
                else:
                    color = base.default_value[:]
                    base.default_value = (*(color[i] * multiplier[i] for i in range(3)), color[3])
        else:
            color = material.diffuse_color[:]
            material.diffuse_color = (*(color[i] * multiplier[i] for i in range(3)), color[3])


def character_frame(objects):
    bpy.context.view_layer.update()
    evaluated = bpy.context.evaluated_depsgraph_get()
    points = [obj.matrix_world @ Vector(corner) for obj in objects
              if obj.type == 'MESH' and obj.visible_get() and not obj.hide_render
              and not all(collection.hide_render for collection in obj.users_collection)
              for corner in obj.evaluated_get(evaluated).bound_box]
    if not points:
        raise ValueError('The character source needs a visible mesh to frame')
    low = Vector(tuple(min(point[i] for point in points) for i in range(3)))
    high = Vector(tuple(max(point[i] for point in points) for i in range(3)))
    return (low + high) / 2, low.z, max(.2, *(high - low))


with open(sys.argv[-1], encoding='utf-8') as source_file:
    params = json.load(source_file)
variant = params.get('character')
center = Vector((0, 0, 1.15))
floor_z, extent = -.015, 1.8
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.name = (params.get('name') or 'Rain and Snow · First scene')[:60]
frame_start, frame_end = 1, 48
for spec in params['sources']:
    before = set(bpy.data.objects)
    collection_name = spec.get('collection')
    with bpy.data.libraries.load(spec['path'], link=False) as (available, target):
        if collection_name:
            target.collections = [collection_name]
            if spec.get('pose'):
                target.actions = [name for name in available.actions if name.startswith('Ellie ')]
        else:
            requested = variant.get('scene') if variant else None
            target.scenes = [requested] if requested else available.scenes[:1]
    if collection_name:
        collection = target.collections[0]
        if collection is None:
            raise ValueError('The selected character collection could not be opened')
        scene.collection.children.link(collection)
    else:
        source = target.scenes[0]
        if source is None:
            raise ValueError('The selected rigged scene could not be opened')
        for collection in source.collection.children:
            scene.collection.children.link(collection)
        for obj in source.collection.objects:
            scene.collection.objects.link(obj)
        if variant:
            frame_start, frame_end = source.frame_start, source.frame_end
    imported = set(bpy.data.objects) - before
    for obj in list(imported):
        if obj.type in ('CAMERA', 'LIGHT'):
            imported.discard(obj)
            bpy.data.objects.remove(obj, do_unlink=True)
    if collection_name and not spec.get('require_rig', True):
        midpoint, base_z, _ = character_frame(imported)
        origin = Vector((midpoint.x, midpoint.y, base_z))
        for obj in imported:
            if obj.parent not in imported:
                obj.location -= origin
    root = bpy.data.objects.new(params['name'] if variant else spec['name'], None)
    scene.collection.objects.link(root)
    for obj in imported:
        if obj.parent not in imported:
            world = obj.matrix_world.copy()
            obj.parent = root
            obj.matrix_world = world
    root.location.x = spec['x']
    present = imported.intersection(scene.objects) if collection_name else imported
    rigs = sorted((obj for obj in present if obj.type == 'ARMATURE'), key=lambda obj: obj.name)
    if not rigs and spec.get('require_rig', True):
        raise ValueError('The selected Blender scene has no armature')
    rig = next((obj for obj in rigs if obj.name.startswith('RIG-')), rigs[0] if rigs else None)
    if spec.get('pose'):
        poses = {action.name: action for action in target.actions if action and action.asset_data}
        pose = poses.get(spec['pose'])
        if pose is None:
            raise ValueError('The selected Ellie pose could not be opened')
        for action in poses.values():
            action.use_fake_user = True
        animation = rig.animation_data_create()
        animation.use_nla = False
        animation.action = pose
        if hasattr(pose, 'slots') and len(pose.slots) == 1:
            animation.action_slot = pose.slots[0]
        frame_start = int(pose.frame_range[0])
        frame_end = frame_start + 47
    if not variant and rig.animation_data:
        rig.animation_data.action = None  # Preserve the rig drivers and constraints.
    bone = rig.pose.bones.get('FK-Head') if rig else None
    if bone and not variant:
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
    if variant:
        root.scale = (variant['height'],) * 3
        root.rotation_euler.z = math.radians(variant['facing'])
        if variant.get('tint'):
            tint_material({slot.material for obj in imported if obj.type == 'MESH'
                           for slot in obj.material_slots if slot.material}, variant['tint'])
        scene.frame_set(frame_start)
        center, floor_z, extent = character_frame(imported)
bpy.ops.mesh.primitive_plane_add(size=max(200, extent * 8), location=(center.x, center.y, floor_z - .002))
floor = bpy.context.object
floor.name = 'Studio floor'
if any(spec.get('collection') for spec in params['sources']):
    floor['lightek_character_floor'] = True
material = bpy.data.materials.new('Warm charcoal')
material.diffuse_color = (.045, .06, .08, 1)
floor.data.materials.append(material)
for name, position, energy, size in [('Key', (2, -4, 6), 1100, 5), ('Fill', (-4, -2, 3), 700, 4), ('Rim', (0, 3, 5), 1400, 3)]:
    data = bpy.data.lights.new(name, 'AREA')
    data.energy, data.size = energy, size
    light = bpy.data.objects.new(name, data)
    scene.collection.objects.link(light)
    light.location = center + Vector(position) * (extent / 1.8) if variant else position
    if variant:
        data.energy *= (extent / 1.8) ** 2
    light.rotation_euler = (center - light.location).to_track_quat('-Z', 'Y').to_euler()
camera = bpy.data.objects.new('Two-shot camera', bpy.data.cameras.new('Two-shot lens'))
scene.collection.objects.link(camera)
camera.location = center + Vector((.2, -3.45, .15)) * extent if variant else (3, -7, 2.7)
camera.rotation_euler = (center - camera.location).to_track_quat('-Z', 'Y').to_euler()
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
scene.frame_start, scene.frame_end = frame_start, frame_end
scene.frame_set(scene.frame_start)
credits = bpy.data.texts.new('Source credits')
if variant:
    for credit in params.get('credits', []):
        if isinstance(credit, dict):
            credits.write(' | '.join(str(credit[key]) for key in ('name', 'credit', 'license', 'license_url', 'source_page')
                                     if credit.get(key)) + '\n')
else:
    credits.write('Rain Rig (CC) Blender Foundation | studio.blender.org\nSnow Rig (CC) Blender Foundation | studio.blender.org\nCC-BY 4.0 https://creativecommons.org/licenses/by/4.0/\n')
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=params['output'], compress=True)
if bpy.data.libraries:
    bpy.ops.file.make_paths_relative()
    bpy.ops.file.pack_libraries()
    bpy.ops.wm.save_as_mainfile(filepath=params['output'], compress=True)
