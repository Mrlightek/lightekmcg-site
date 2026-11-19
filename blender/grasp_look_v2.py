"""Stylized head nod and downward pupil drawing for a nearby handling target.

This is a production drawing control, not a new general eyeball/neck solver.
"""
import math
import bpy
from mathutils import Vector,Matrix
from bench_v1 import source,key_pose

def bake(root,profile,target):
    rig=source(root,profile['mechanics']['rig']);head=rig.pose.bones['Head'];scene=bpy.context.scene
    objects={obj.get('lightek_source_object'):obj for obj in root.children_recursive}
    originals=[];degrees=[]
    # FaceEyes is a joined drawing: move colored iris/pupil/catchlight vertices,
    # preserving the white sclera and existing blink/viseme controls.
    for name in ('FaceEyes','Side pupil','Side pupil reverse'):
        obj=objects.get(name)
        if obj is None:continue
        if name=='FaceEyes':
            indices={v for polygon in obj.data.polygons if 'white' not in obj.data.materials[polygon.material_index].name.lower() for v in polygon.vertices}
        else:indices=set(range(len(obj.data.vertices)))
        if not obj.data.shape_keys:obj.shape_key_add(name='Basis')
        key=obj.shape_key_add(name='grasp_look_down_v2')
        # Local mesh coordinates may carry source scaling; convert world metres.
        offset=obj.matrix_world.inverted().to_3x3() @ Vector((0,0,-.025))
        for i in indices:key.data[i].co+=offset
        key.value=1
        originals.append(obj.name)
    bases=[]
    for frame in range(1,97):
        scene.frame_set(frame);bpy.context.view_layer.update();bases.append(head.matrix.copy())
    for frame in range(1,97):
        scene.frame_set(frame);head.matrix=bases[frame-1];bpy.context.view_layer.update();base=bases[frame-1]
        eye=rig.matrix_world @ Vector(profile['attention_binding']['eye_anchor']);delta=target.matrix_world.translation-eye
        nod=max(20,min(45,math.degrees(math.atan2(-delta.z,math.hypot(delta.x,delta.y)))-25))
        head.matrix=Matrix.Translation(base.translation) @ Matrix.Rotation(math.radians(nod),4,'X') @ Matrix.Translation(-base.translation) @ base
        bpy.context.view_layer.update();key_pose(head,frame);degrees.append(nod)
    return {'target':target.name,'head_nod_deg':[min(degrees),max(degrees)],'pupil_down_m':.025,'drawing_objects':originals,'mode':'stylized_head_and_pupil_attention'}
