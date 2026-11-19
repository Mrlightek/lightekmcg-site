"""Versioned action coordinator with injected calibrated kinematic drivers."""
import json
import math
import bpy
from mathutils import Vector, Matrix, Quaternion
import kinematics_v1 as kinematics
import hashlib
from pathlib import Path

TOLERANCE=.002
def smooth(value):
    value=max(0,min(1,value));return value*value*(3-2*value)
def source(root,name):
    obj=next((obj for obj in root.children_recursive if obj.get('lightek_source_object')==name),None)
    if obj is None:raise RuntimeError('Missing mechanics source binding: '+name)
    return obj
def key_pose(bone,frame):
    bone.rotation_mode='QUATERNION'
    for path in ('location','rotation_quaternion'):bone.keyframe_insert(data_path=path,frame=frame,group='Lightek mechanics v1')
def key_object(obj,frame):
    for path in ('location','rotation_quaternion','scale'):obj.keyframe_insert(data_path=path,frame=frame,group='Lightek mechanics v1')

class BenchV1:
    @staticmethod
    def fingerprint():
        root=Path(__file__).parent
        return hashlib.sha256(b''.join((root/name).read_bytes() for name in ('bench_v1.py','kinematics_v1.py'))).hexdigest()
    phases={'walk':[0,2],'turn':[2,2.5],'sit':[2.5,3.25],'seated':[3.25,6.4],'stand':[6.4,7.25],'rest':[7.25,8]}
    def foot(self,side,t):
        # Alternating stance/swing with explicit world-space support anchors.
        offset=-.17 if side=='L' else .17
        point=Vector((-.8+offset,-.24,.104))
        windows=[(i*.25,(i+1)*.25) for i in range(8) if i%2==(0 if side=='L' else 1)]
        windows.append((2,2.25) if side=='L' else (2.25,2.5))
        planted=True
        for start,end in windows:
            landing=Vector((-.8+.8*smooth(min(end,2)/2)+offset,-.24,.104))
            if t>=end:point=landing
            elif t>start:
                ratio=(t-start)/(end-start);point=point.lerp(landing,smooth(ratio));point.z+=math.sin(math.pi*ratio)*.07
                planted=False;break
            else:break
        return point,planted
    def bake(self,item,root,target):
        scene=bpy.context.scene;plan=item['definition']['mechanics_plan'];profile=item['definition']['character_profile'].get('mechanics',{})
        if plan.get('driver_fingerprint')!=self.fingerprint():raise RuntimeError('The pinned mechanics implementation changed; prepare a reviewed new performance')
        if plan.get('profile')!='illustrated_biped' or profile.get('profile')!=plan['profile'] or profile.get('version')!=1 or plan.get('source_blob_id')!=item['definition']['character_profile'].get('source_blob_id') or plan.get('phases')!=self.phases:
            raise RuntimeError('The pinned mechanics profile or plan is incompatible')
        if scene.render.fps!=12 or scene.render.fps_base!=1 or scene.frame_start!=1 or scene.frame_end!=96:
            raise RuntimeError('Bench v1 requires an eight-second 12 fps scene')
        if (target.location-Vector((0,.27,.40))).length>.00001 or (target.scale-Vector((.8,.19,.04))).length>.00001 or any(abs(v)>.00001 for v in target.rotation_euler):
            raise RuntimeError('Bench v1 needs its calibrated static seat')
        rig=source(root,profile['rig']);body=rig.pose.bones.get(profile['body']);support=source(root,profile['support'])
        if not body or rig.type!='ARMATURE' or support.parent!=rig or support.parent_bone!=body.name:raise RuntimeError('Missing bound body/support rig')
        if any(abs(v-1)>.00001 for v in rig.matrix_world.to_scale()):raise RuntimeError('Bench v1 needs its unscaled calibrated rig')
        legs={}
        for side,binding in profile['legs'].items():
            upper=rig.pose.bones.get(binding['upper']);lower=rig.pose.bones.get(binding['lower']);foot=source(root,binding['foot'])
            if not upper or not lower or lower.parent!=upper or upper.parent!=body or not lower.bone.use_connect or foot.parent!=rig or foot.parent_bone!=lower.name:raise RuntimeError('Missing connected calibrated leg')
            sign=-1 if side=='L' else 1
            if (upper.bone.head_local-Vector((sign*.17,0,.86))).length>.00001 or abs(upper.bone.length-.38)>.00001 or abs(lower.bone.length-.376)>.00001 or abs(min(v[2] for v in foot.bound_box)+.104)>.00001:raise RuntimeError('Leg proportions or sole geometry differ from calibration v1')
            legs[side]=(upper,lower,foot)
        if abs(min(v[2] for v in support.bound_box)+.0832)>.00001:raise RuntimeError('Pelvis support geometry differs from calibration v1')
        if set(legs)!={'L','R'}:raise RuntimeError('Bench v1 requires two calibrated legs')
        arms={}
        for side,binding in profile['arms'].items():
            upper=rig.pose.bones.get(binding['upper']);lower=rig.pose.bones.get(binding['lower']);hand=source(root,binding['hand'])
            if not upper or not lower or upper.parent!=body or lower.parent!=upper or not lower.bone.use_connect or hand.parent!=rig or hand.parent_bone!=lower.name:raise RuntimeError('Missing calibrated lap arm')
            arms[side]=(upper,lower,hand)
        if set(arms)!={'L','R'}:raise RuntimeError('Bench v1 requires both lap arms')
        records=[]
        for frame in range(1,97):
            scene.frame_set(frame);t=(frame-1)/12
            sit=smooth((t-2.5)/.75)*(1-smooth((t-6.4)/.85))
            rest=smooth((t-7.25)/.75)
            drop=(-.05*(1-sit)-.2568*sit)*(1-rest)
            root.location=Vector((-.8+.8*smooth(t/2),-.24+.46*sit,0))
            root.rotation_mode='QUATERNION';root.rotation_quaternion=Quaternion((0,0,1),math.radians(20)*(1-smooth((t-2)/.5)))
            key_object(root,frame);bpy.context.view_layer.update()
            matrix=body.bone.matrix_local.copy();matrix.translation+=Vector((0,0,drop));body.matrix=matrix
            key_pose(body,frame);bpy.context.view_layer.update()
            row={'frame':frame,'seated':3.25<=t<=6.4,'feet':{}}
            for side,(upper,lower,foot) in legs.items():
                ankle,planted=self.foot(side,t)
                target_local=rig.matrix_world.inverted() @ ankle
                shoulder=upper.bone.head_local+Vector((0,0,drop))
                pole=rig.matrix_world.inverted().to_3x3() @ Vector((0,-1,0))
                knee=kinematics.elbow(shoulder,target_local,upper.bone.length,lower.bone.length,pole)
                for bone,start,end in ((upper,shoulder,knee),(lower,knee,target_local)):
                    rest_q=bone.bone.matrix_local.to_quaternion()
                    rotation=(rest_q @ Vector((0,1,0))).rotation_difference((end-start).normalized()) @ rest_q
                    bone.matrix=Matrix.LocRotScale(start,rotation,Vector((1,1,1)));bpy.context.view_layer.update();key_pose(bone,frame)
                foot.rotation_mode='QUATERNION';foot.matrix_world=Matrix.Translation(ankle+Vector((0,-.09,0)))
                key_object(foot,frame)
                row['feet'][side]={'ankle':list(ankle),'planted':planted}
            for side,(upper,lower,hand) in arms.items():
                sign=-1 if side=='L' else 1
                origin=(rig.matrix_world @ Vector((sign*.43,-.01,.72+drop))).lerp(Vector((sign*.30,-.10,.68)),sit)
                rotation=root.rotation_quaternion.copy();wrist=origin+rotation @ Vector((0,0,.12))
                target_local=rig.matrix_world.inverted() @ wrist;shoulder=upper.bone.head_local+Vector((0,0,drop))
                pole=rig.matrix_world.inverted().to_3x3() @ Vector((sign,-1,0))
                elbow=kinematics.elbow(shoulder,target_local,upper.bone.length,lower.bone.length,pole)
                for bone,start,end in ((upper,shoulder,elbow),(lower,elbow,target_local)):
                    rest_q=bone.bone.matrix_local.to_quaternion()
                    q=(rest_q @ Vector((0,1,0))).rotation_difference((end-start).normalized()) @ rest_q
                    bone.matrix=Matrix.LocRotScale(start,q,Vector((1,1,1)));bpy.context.view_layer.update();key_pose(bone,frame)
                hand.rotation_mode='QUATERNION';hand.matrix_world=Matrix.LocRotScale(origin,rotation,Vector((1,1,1)));key_object(hand,frame)
            records.append(row)
        errors=[];seats=[];stance=[]
        for row in records:
            scene.frame_set(row['frame']);bpy.context.view_layer.update()
            for side,(upper,lower,foot) in legs.items():
                expected=Vector(row['feet'][side]['ankle']);ankle=rig.matrix_world @ lower.tail
                errors.extend([(ankle-expected).length,((foot.matrix_world @ Vector((0,.09,0)))-ankle).length])
                if row['feet'][side]['planted']:stance.append(abs((foot.matrix_world @ Vector((0,.004,-.104))).z))
            for upper,lower,hand in arms.values():
                errors.append(((hand.matrix_world @ Vector((0,0,.12)))-(rig.matrix_world @ lower.tail)).length)
            if row['seated']:
                point=support.matrix_world @ Vector((0,.004,-.0832));local=target.matrix_world.inverted() @ point
                if abs(local.x)>1 or abs(local.y)>1:raise RuntimeError('Pelvis support is outside the seat')
                seats.append(abs(point.z-(target.matrix_world @ Vector((0,0,1))).z))
        if not seats or max(errors+seats+stance)>TOLERANCE:raise RuntimeError('Mechanics support/contact failed the 2 mm tolerance')
        report={'actor_id':item['id'],'driver':'bench','version':1,'frames':96,'max_limb_error':max(errors),'max_seat_error':max(seats),'max_ground_error':max(stance),'support_frames':len(seats),'phases':self.phases}
        root['lightek_mechanics_report']=json.dumps(report)
        return {'actor_id':str(item['id']),'target_id':str(plan['target_object_id']),'contact_mesh':support,'first':40,'last':77,'point':Vector((0,0,1)),'normal':Vector((0,0,1))}
