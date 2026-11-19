"""Create an original, editable toon performer with face controls and pose bones."""
import bpy
import json
import math
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).parent))
from mathutils import Vector

params_path, output = sys.argv[sys.argv.index('--') + 1:]
with open(params_path, encoding='utf-8') as handle:
    params = json.load(handle)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.name = 'Lightek Performer'
illustrated = params.get('style') == 'illustrated'


def material(name, hex_color, roughness=0.5):
    color = tuple(int(hex_color[i:i+2], 16)/255 for i in (1, 3, 5)) + (1,)
    m = bpy.data.materials.new(name); m.diffuse_color = color; m.use_nodes = True
    if illustrated:
        nodes=m.node_tree.nodes;nodes.clear()
        emission=nodes.new('ShaderNodeEmission');output=nodes.new('ShaderNodeOutputMaterial')
        linear=tuple(c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in color[:3])
        emission.inputs['Color'].default_value=(*linear,1)
        m.node_tree.links.new(emission.outputs[0],output.inputs['Surface'])
        return m
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
    if illustrated:
        count=32
        points=[(math.cos(i*math.tau/count),math.sin(i*math.tau/count)) for i in range(count)]
        if name=='Head': points=[(-.8,.5),(-.65,.9),(.6,1),(.93,.55),(.72,-.55),(.25,-1),(-.3,-1),(-.82,-.5)]
        if name=='Shirt': points=[(-1,1),(1,1),(.45,-.5),(0,-1),(-.45,-.5)]
        if name=='Jacket body': points=[(-.6,1),(.6,1),(1,.7),(.8,-.5),(.5,-1),(-.5,-1),(-.8,-.5),(-1,.7)]
        count=len(points)
        vertices=[(x*scale[0],0,z*scale[2]) for x,z in points]+[(x*scale[0]*1.04,.004,z*scale[2]*1.04) for x,z in points]
        mesh=bpy.data.meshes.new(name+' drawing');mesh.from_pydata(vertices,[],[list(range(count)),list(range(count,count*2))]);mesh.materials.append(mat);mesh.materials.append(black)
        mesh.polygons[1].material_index=1
        obj=bpy.data.objects.new(name,mesh);scene.collection.objects.link(obj);obj.location=location
        return obj
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=20, location=location)
    obj = bpy.context.object; obj.name = name
    obj.scale = scale; bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    for face in obj.data.polygons: face.use_smooth = True
    return obj


body = sphere('Jacket body', (0,0,1.17) if illustrated else (0,0,.98), (.40,.24,.34) if illustrated else (.40,.24,.52), wardrobe)
sphere('Shirt', (0, -0.21, 1.12), (0.22, 0.045, 0.30), black)
sphere('Neck', (0, 0, 1.49), (0.14, 0.14, 0.20), skin)
head = sphere('Head', (0, 0, 1.88), (0.34, 0.28, 0.42), skin)
head_parts = [head]
head_parts += [sphere('Ear L', (-0.34, 0, 1.86), (0.065, 0.06, 0.12), skin), sphere('Ear R', (0.34, 0, 1.86), (0.065, 0.06, 0.12), skin)]
head_parts += [sphere('Nose', (0, -0.285, 1.88), (0.065, 0.075, 0.10), skin)]
hair_style = params.get('hair_style', 'curls')
if hair_style == 'close':
    head_parts.append(sphere('Close cut', (0, 0.026, 2.155), (0.31, 0.245, 0.14), hair))
elif hair_style == 'high_top':
    head_parts.append(sphere('High top', (0, 0.03, 2.25), (0.32, 0.24, 0.22), hair))
else:
    head_parts.append(sphere('Hair cap', (0, 0.035, 2.17), (0.33, 0.26, 0.18), hair))
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
# Distinct editable mouth silhouettes for the Rhubarb A–H / rest vocabulary.
for label, (width, height, lift) in {
    'a': (1.0, .15, 0), 'b': (1.05, 1.6, 0), 'c': (1.0, 4.5, 0),
    'd': (.95, 8, 0), 'e': (.65, 5, 0), 'f': (.38, 3.6, 0),
    'g': (1.05, 1, .012), 'h': (1.0, 3, .018), 'x': (.9, .45, 0),
}.items():
    key = mouth.shape_key_add(name='viseme_'+label)
    for point in key.data:
        point.co.x *= width
        point.co.z = 1.72 + (point.co.z-1.72)*height + lift
head_parts.append(mouth)

# A photo is a packed texture on a curved face panel. The rig still drives the head
# and the existing mouth shapes, independently of the photo.
portrait_path = Path(params_path).with_name('portrait.png')
if portrait_path.is_file():
    photo = bpy.data.images.load(str(portrait_path), check_existing=False)
    photo.pack()
    photo.filepath = '//portrait.png'
    portrait = bpy.data.materials.new('Character portrait')
    portrait.use_nodes = True
    nodes = portrait.node_tree.nodes
    texture = nodes.new('ShaderNodeTexImage'); texture.image = photo
    portrait.node_tree.links.new(texture.outputs['Color'], nodes.get('Principled BSDF').inputs['Base Color'])
    radius_x, radius_z, center_z = 0.258, 0.247, 2.0
    vertices = [(0, -0.345, center_z)]
    uvs = [(0.5, 0.66)]
    for i in range(48):
        angle = i * math.tau / 48
        x, z = math.cos(angle), math.sin(angle)
        vertices.append((radius_x*x, -0.332, center_z+radius_z*z))
        uvs.append((0.5+0.47*x, 0.66+0.26*z))
    triangles = [(0, 1+i, 1+(i+1)%48) for i in range(48)]
    panel_mesh = bpy.data.meshes.new('Portrait surface')
    panel_mesh.from_pydata(vertices, [], triangles)
    panel_mesh.materials.append(portrait)
    uv_layer = panel_mesh.uv_layers.new()
    for loop in panel_mesh.loops:
        uv_layer.data[loop.index].uv = uvs[loop.vertex_index]
    panel = bpy.data.objects.new('Face portrait', panel_mesh)
    scene.collection.objects.link(panel)
    head_parts.append(panel)
    mouth.location.y = -0.1


arm_parts = {};forearm_parts={}
for side, x in [('L', -0.43), ('R', 0.43)]:
    if illustrated:
        arm_parts[side]=[sphere('Upper sleeve '+side,(x,0,1.21),(.12,.14,.15),wardrobe)]
        forearm_parts[side]=[sphere('Lower sleeve '+side,(x,0,.99),(.07,.12,.09),wardrobe),sphere('Hand '+side,(x,-.01,.72),(.10,.09,.12),skin)]
    else:
        arm_parts[side] = [sphere('Sleeve '+side, (x, 0, 1.05), (0.12, 0.14, 0.36), wardrobe), sphere('Hand '+side, (x, -0.01, 0.72), (0.10, 0.09, 0.12), skin)]
leg_parts = {};shin_parts={}
for side,x in [('L',-.17),('R',.17)]:
    if illustrated:
        leg_parts[side]=[sphere('Thigh '+side,(x,0,.67),(.13,.14,.20),trousers)]
        shin_parts[side]=[sphere('Calf '+side,(x,0,.29),(.11,.12,.19),trousers),sphere('Boot '+side,(x,-.09,.104),(.15,.20,.10),black)]
    else:
        leg_parts[side]=[sphere('Trouser leg '+side,(x,0,.43),(.15,.16,.43),trousers),sphere('Boot '+side,(x,-.09,.08),(.17,.24,.10),black)]
if illustrated:sphere('Pelvis support',(0,0,.78),(.30,.14,.08),trousers)
sphere('Jacket pin', (0.24, -0.221, 1.28), (0.035, 0.025, 0.035), gold)

rig = bpy.data.objects.new('PerformerRig', bpy.data.armatures.new('Performer bones')); scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig; rig.select_set(True); bpy.ops.object.mode_set(mode='EDIT')
for name, a, b in [('Head', (0, 0, 1.48), (0, 0, 2.2)), ('Arm.L', (-0.35, 0, 1.35), (-0.43, 0, 0.72)), ('Arm.R', (0.35, 0, 1.35), (0.43, 0, 0.72)), ('Leg.L',(-.17,0,.86),(-.17,0,.08)), ('Leg.R',(.17,0,.86),(.17,0,.08))]:
    bone = rig.data.edit_bones.new(name); bone.head = a; bone.tail = b
if illustrated:
    body=rig.data.edit_bones.new('Body');body.head=(0,0,.86);body.tail=(0,0,1.4)
    for name in ('Head','Arm.L','Arm.R','Leg.L','Leg.R'):rig.data.edit_bones[name].parent=body
    for side,x in [('L',-.17),('R',.17)]:
        upper=rig.data.edit_bones['Leg.'+side];upper.tail=(x,0,.48)
        lower=rig.data.edit_bones.new('Shin.'+side);lower.head=upper.tail;lower.tail=(x,0,.104);lower.parent=upper;lower.use_connect=True
    for side,x in [('L',-.43),('R',.43)]:
        upper=rig.data.edit_bones['Arm.'+side];upper.tail=(x,0,1.08)
        lower=rig.data.edit_bones.new('Forearm.'+side);lower.head=upper.tail;lower.tail=(x,-.01,.84);lower.parent=upper;lower.use_connect=True
bpy.ops.object.mode_set(mode='OBJECT')
parts_by_bone=[('Head', head_parts), ('Arm.L', arm_parts['L']), ('Arm.R', arm_parts['R']),('Leg.L',leg_parts['L']),('Leg.R',leg_parts['R'])]
if illustrated:parts_by_bone += [('Forearm.'+side,parts) for side,parts in forearm_parts.items()]+[('Shin.'+side,parts) for side,parts in shin_parts.items()]
for bone_name,parts in parts_by_bone:
    for obj in parts:
        world = obj.matrix_world.copy(); obj.parent = rig; obj.parent_type = 'BONE'; obj.parent_bone = bone_name
        bpy.context.view_layer.update(); obj.matrix_world = world

if illustrated:
    for obj in list(scene.objects):
        if obj.type=='MESH' and obj.parent is None:
            world=obj.matrix_world.copy();obj.parent=rig;obj.parent_type='BONE';obj.parent_bone='Body'
            bpy.context.view_layer.update();obj.matrix_world=world

if illustrated:
    import create_side_views
    create_side_views.build(rig)

# Stashed native Actions are reusable clips, not automatically playing animation.
for name, bone_name, axis, amplitude in [('Head nod','Head',0,.25),('Look left and right','Head',2,.35),('Wave right','Arm.R',2,.7)]:
    animation=rig.animation_data_create();animation.action=None
    bone=rig.pose.bones[bone_name];bone.rotation_mode='XYZ'
    for frame, value in [(1,0),(7,amplitude),(13,0),(19,-amplitude),(25,0)]:
        bone.rotation_euler=(0,0,0);bone.rotation_euler[axis]=value
        bone.keyframe_insert(data_path='rotation_euler',frame=frame,group=bone_name)
    action=animation.action;action.name=name
    slot=getattr(animation,'action_slot',None)
    track=animation.nla_tracks.new();track.name='Source · '+name
    strip=track.strips.new(name,1,action)
    if slot is not None and hasattr(strip,'action_slot'):strip.action_slot=slot
    track.mute=True;animation.action=None
# Additional illustrated puppet Actions are opt-in. Existing saved sources and
# the legacy toon motion vocabulary retain their own registered identities.
if illustrated:
    for name in ('Step in place','Point left','Point right'):
        animation=rig.animation_data_create();animation.action=None
        for pose in rig.pose.bones: pose.rotation_mode='XYZ';pose.rotation_euler=(0,0,0)
        for frame in (1,7,13,19,25):
            ratio=(frame-1)/24
            if name=='Step in place':
                for bone_name,sign,amplitude in [('Leg.L',1,.28),('Leg.R',-1,.28),('Arm.L',-1,.14),('Arm.R',1,.14)]:
                    bone=rig.pose.bones[bone_name];bone.rotation_euler=(0,0,sign*math.sin(ratio*math.tau)*amplitude)
                    bone.keyframe_insert(data_path='rotation_euler',frame=frame,group=bone_name)
            else:
                side='L' if name=='Point left' else 'R'
                bone=rig.pose.bones['Arm.'+side]
                amount=0 if frame in (1,25) else (1 if side=='L' else -1)*1.15
                bone.rotation_euler=(0,0,amount);bone.keyframe_insert(data_path='rotation_euler',frame=frame,group='Arm.'+side)
        action=animation.action;action.name=name
        slot=getattr(animation,'action_slot',None)
        track=animation.nla_tracks.new();track.name='Source · '+name
        strip=track.strips.new(name,1,action)
        if slot is not None and hasattr(strip,'action_slot'):strip.action_slot=slot
        track.mute=True;animation.action=None
    for pose in rig.pose.bones:pose.rotation_euler=(0,0,0)
scene.frame_set(1)

camera = bpy.data.objects.new('Portrait camera', bpy.data.cameras.new('Portrait lens')); scene.collection.objects.link(camera)
camera.location = (0, -5, 1.7); camera.rotation_euler = (Vector((0, 0, 1.5))-camera.location).to_track_quat('-Z', 'Y').to_euler(); camera.data.lens = 60; scene.camera = camera
for name, loc, power, size in [('Key', (3, -4, 5), 800, 4), ('Fill', (-3, -2, 3), 400, 4), ('Rim', (1, 2, 4), 900, 3)]:
    light = bpy.data.objects.new(name, bpy.data.lights.new(name, 'AREA')); scene.collection.objects.link(light); light.location = loc; light.data.energy = power; light.data.shape = 'DISK'; light.data.size = size; light.rotation_euler = (Vector((0, 0, 1.3))-light.location).to_track_quat('-Z', 'Y').to_euler()
if illustrated:
    scene.view_settings.view_transform='Standard'
    scene['lightek_character_style']='illustrated'
scene.world = bpy.data.worlds.new('Studio world'); scene.world.color = (0.07, 0.08, 0.12)
scene.render.engine = 'CYCLES'; scene.cycles.samples = 8; scene.render.resolution_x = 512; scene.render.resolution_y = 512; scene.render.resolution_percentage = 100
bpy.ops.wm.save_as_mainfile(filepath=output)
