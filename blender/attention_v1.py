"""Bounded head-only scene focal points, including direct address to active camera."""
import bpy,json,math,hashlib
from pathlib import Path
from mathutils import Vector,Matrix
from bench_v1 import source,key_pose

def fingerprint():return hashlib.sha256(b''.join((Path(__file__).parent/name).read_bytes() for name in ('attention_v1.py','spatial_frame_v1.py'))).hexdigest()
def mirror_face(obj,objects,frame):
    original=objects.get(obj.get('lightek_mirror_source'))
    if not original or not obj.data.shape_keys or not original.data.shape_keys:return
    for key in obj.data.shape_keys.key_blocks:
        if key.name!='Basis' and key.name in original.data.shape_keys.key_blocks:
            key.value=original.data.shape_keys.key_blocks[key.name].value
            key.keyframe_insert(data_path='value',frame=frame)

def apply(objects,created):
    scene=bpy.context.scene;original=scene.frame_current;indexed={str(row['id']):row for row in objects}
    for row in objects:
        definition=row.get('definition',{});plan=definition.get('attention_plan')
        if not plan:continue
        if plan.get('version')!=1 or plan.get('driver_fingerprint')!=fingerprint():raise RuntimeError('The pinned attention driver changed')
        if scene.frame_end-scene.frame_start+1>96:raise RuntimeError('Guided attention supports at most 96 frames')
        root=created[str(row['id'])];source_objects={obj.get('lightek_source_object'):obj for obj in root.children_recursive};profile=definition['character_profile'];binding=profile.get('bones',{}).get('head')
        if not binding:raise RuntimeError('Attention requires a bound head')
        calibration=profile.get('attention_binding')
        if not calibration or calibration.get('rig')!=binding['object'] or calibration.get('head')!=binding['bone']:raise RuntimeError('Register a calibrated eye anchor for attention')
        rig=source(root,binding['object']);head=rig.pose.bones.get(binding['bone'])
        if not head:raise RuntimeError('The bound attention head is unavailable')
        target=None
        if plan['kind']=='object':target=created.get(str(plan.get('target_object_id')))
        elif plan['kind']!='camera':raise RuntimeError('Unknown focal point kind')
        if plan['kind']=='object' and (not target or target==root):raise RuntimeError('The scene focal point is missing')
        bases=[];fps=scene.render.fps/scene.render.fps_base
        for frame in range(scene.frame_start,scene.frame_end+1):
            scene.frame_set(frame);bpy.context.view_layer.update();bases.append(head.matrix.copy())
        local_forward=head.bone.matrix_local.to_quaternion().inverted() @ Vector((0,-1,0));rest_eye=Vector(calibration['eye_anchor']);rest_inverse=head.bone.matrix_local.inverted();errors=[];clamped=0;active=[]
        for offset,frame in enumerate(range(scene.frame_start,scene.frame_end+1)):
            scene.frame_set(frame);seconds=(frame-1)/fps;base=bases[offset];head.matrix=base;bpy.context.view_layer.update()
            if not plan['start']<=seconds<plan['end']:
                key_pose(head,frame)
                if profile.get('views') and scene.camera:
                    eye=rig.matrix_world @ head.matrix @ rest_inverse @ rest_eye;forward=rig.matrix_world.to_quaternion() @ head.matrix.to_quaternion() @ local_forward;front=forward.dot((scene.camera.matrix_world.translation-eye).normalized())>=math.cos(math.pi/4)
                    for view in ('front','side'):
                        for name in profile['views'][view]:
                            obj=source(root,name)
                            if obj.parent==rig and obj.parent_type=='BONE' and obj.parent_bone==head.name:
                                obj.hide_render=(view=='front')!=front;obj.hide_viewport=obj.hide_render if view=='side' else False
                                obj.keyframe_insert(data_path='hide_render',frame=frame);obj.keyframe_insert(data_path='hide_viewport',frame=frame)
                                mirror_face(obj,source_objects,frame)
                continue
            camera=scene.camera;focus=camera if plan['kind']=='camera' else target
            if focus is None:raise RuntimeError('The active camera focal point is missing')
            point=focus.matrix_world.translation.copy()
            target_profile=indexed.get(str(plan.get('target_object_id')),{}).get('definition',{}).get('character_profile')
            if target_profile:
                other=target_profile.get('bones',{}).get('head')
                if other:
                    other_rig=source(focus,other['object']);other_head=other_rig.pose.bones[other['bone']]
                    other_calibration=target_profile.get('attention_binding',{})
                    anchor=Vector(other_calibration.get('eye_anchor',other_head.bone.head_local+other_head.bone.vector*.7))
                    parent_delta=other_head.parent.matrix @ other_head.parent.bone.matrix_local.inverted() if other_head.parent else Matrix.Identity(4)
                    point=other_rig.matrix_world @ parent_delta @ anchor
            root_q=root.matrix_world.to_quaternion();rig_q=rig.matrix_world.to_quaternion();limited=False
            for _ in range(4):
                eye=rig.matrix_world @ head.matrix @ rest_inverse @ rest_eye;delta=point-eye
                if delta.length<.01:raise RuntimeError('The focal point is too close to the eyes')
                local=root_q.inverted() @ delta.normalized();yaw=math.atan2(local.x,-local.y);pitch=math.atan2(local.z,math.hypot(local.x,local.y))
                y=max(-math.radians(75),min(math.radians(75),yaw));p=max(-math.radians(25),min(math.radians(25),pitch));limited=limited or abs(y-yaw)>.00001 or abs(p-pitch)>.00001
                desired=root_q @ Vector((math.sin(y)*math.cos(p),-math.cos(y)*math.cos(p),math.sin(p)))
                current=rig_q @ base.to_quaternion() @ local_forward;turn=current.rotation_difference(desired)
                q=rig_q.inverted() @ turn @ rig_q @ base.to_quaternion();head.matrix=Matrix.LocRotScale(base.translation,q,base.to_scale());bpy.context.view_layer.update()
            key_pose(head,frame);clamped+=int(limited);active.append((frame,point.copy()))
            # Head artwork follows attention independently from body-facing artwork.
            if profile.get('views') and camera:
                eye=rig.matrix_world @ head.matrix @ rest_inverse @ rest_eye;forward=rig_q @ head.matrix.to_quaternion() @ local_forward;front=forward.dot((camera.matrix_world.translation-eye).normalized())>=math.cos(math.pi/4)
                for view,names in ((key,profile['views'][key]) for key in ('front','side')):
                    for name in names:
                        obj=source(root,name)
                        if obj.parent==rig and obj.parent_type=='BONE' and obj.parent_bone==head.name:
                            obj.hide_render=(view=='front')!=front;obj.hide_viewport=obj.hide_render if view=='side' else False
                            obj.keyframe_insert(data_path='hide_render',frame=frame);obj.keyframe_insert(data_path='hide_viewport',frame=frame)
                            mirror_face(obj,source_objects,frame)
        for frame,point in active:
            scene.frame_set(frame);bpy.context.view_layer.update();eye=rig.matrix_world @ head.matrix @ rest_inverse @ rest_eye
            forward=rig.matrix_world.to_quaternion() @ head.matrix.to_quaternion() @ local_forward;errors.append(math.degrees(forward.angle((point-eye).normalized())))
        root['lightek_attention_report']=json.dumps({'version':1,'kind':plan['kind'],'frames':len(active),'clamped_frames':clamped,'max_aim_error_degrees':max(errors,default=0)})
    scene.frame_set(original);bpy.context.view_layer.update()
