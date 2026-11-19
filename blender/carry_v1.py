"""Rigid palm attachment, direction-aware carrying and supported release."""
import json,hashlib
from pathlib import Path
import bpy
from mathutils import Vector
from bench_v1 import smooth
from biped_v2 import Biped,FootTracks,rotation
import views_v1
import spatial_checks

class CarryV1:
    requires_world=True
    target_tag='mechanics_carry'
    phases={'reach':[0,.75],'grip':[.75,1],'lift':[1,1.75],'turn_out':[1.75,2.25],'walk':[2.25,4.25],'turn_in':[4.25,4.75],'place':[4.75,5.5],'release':[5.5,6],'rest':[6,8]}
    files=('carry_v1.py','biped_v2.py','views_v1.py','spatial_frame_v1.py','bench_v1.py','kinematics_v1.py')
    @classmethod
    def fingerprint(cls):return hashlib.sha256(b''.join((Path(__file__).parent/name).read_bytes() for name in cls.files)).hexdigest()
    def __init__(self,objects,created):self.objects=objects;self.created=created
    def hand(self,t,position,yaw,drop):
        initial=Vector((-.83,-.66,.72+drop));pickup=Vector((-.83,-.154,1.21));up=Vector((-.83,-.23,1.36));q=rotation(yaw)
        held=position+q @ Vector((-.38,-.28,1.28));put=Vector((-.03,-.154,1.21));approach=Vector((-.03,-.23,1.36));rest=Vector((-.03,-.66,.72+drop))
        if t<.375:return initial.lerp(Vector((-.83,-.66,1.29)),smooth(t/.375))
        if t<.75:return Vector((-.83,-.66,1.29)).lerp(pickup,smooth((t-.375)/.375))
        if t<1:return pickup
        if t<1.25:return pickup.lerp(up,smooth((t-1)/.25))
        if t<1.375:return up.lerp(Vector((-.98,-.23,1.36)),smooth((t-1.25)/.125))
        if t<1.60:return Vector((-.98,-.23,1.36)).lerp(Vector((-.98,-.93,1.28)),smooth((t-1.375)/.225))
        if t<1.75:return Vector((-.98,-.93,1.28)).lerp(held,smooth((t-1.60)/.15))
        if t<4.75:return held
        if t<4.9:return held.lerp(Vector((-.18,-.93,1.36)),smooth((t-4.75)/.15))
        if t<5.1:return Vector((-.18,-.93,1.36)).lerp(Vector((-.18,-.23,1.36)),smooth((t-4.9)/.2))
        if t<5.25:return Vector((-.18,-.23,1.36)).lerp(approach,smooth((t-5.1)/.15))
        if t<5.5:return approach.lerp(put,smooth((t-5.25)/.25))
        if t<5.75:return put.lerp(Vector((-.03,-.30,1.21)),smooth((t-5.5)/.25))
        if t<6:return Vector((-.03,-.30,1.21)).lerp(rest,smooth((t-5.75)/.25))
        return rest
    def bake(self,item,root,target):
        scene=bpy.context.scene;definition=item['definition'];plan=definition['mechanics_plan'];profile=definition['character_profile'];indexed={str(row['id']):row for row in self.objects}
        if plan.get('driver_fingerprint')!=self.fingerprint() or plan.get('source_blob_id')!=profile.get('source_blob_id') or plan.get('phases')!=self.phases:raise RuntimeError('The pinned carry implementation changed')
        if scene.frame_start!=1 or scene.frame_end!=96 or scene.render.fps!=12 or scene.render.fps_base!=1:raise RuntimeError('Carry v1 requires eight seconds at 12 fps')
        expected={'pickup':(-.83,.02,.90),'putdown':(-.03,.02,.90)};supports={}
        if set(plan.get('support_object_ids',{}))!=set(expected):raise RuntimeError('Both carry support references are required')
        for role,key in plan['support_object_ids'].items():
            row=indexed.get(str(key));obj=self.created.get(str(key))
            if not row or row['type']!='cube' or obj is None or row['definition'].get('mechanics_support')!=role or any(row['definition'].get(k) for k in ('animation','story_relation','authoring_commands')) or (obj.location-Vector(expected[role])).length>.00001 or (obj.scale-Vector((.18,.20,.05))).length>.00001 or any(abs(v)>.00001 for v in obj.rotation_euler):raise RuntimeError('Use the two calibrated static carry tables')
            supports[role]=obj
        if len({target,*supports.values()})!=3 or (target.location-Vector((-.83,-.1,1.08))).length>.00001 or (target.scale-Vector((.12,.05,.13))).length>.00001 or any(abs(v)>.00001 for v in target.rotation_euler):raise RuntimeError('Use the calibrated carry parcel')
        actor=Biped(root,profile['mechanics']);tracks=FootTracks(-.4,-.65,0);tracks.turn(1.75,2.25,-.4,-.65,90);tracks.walk(2.25,4.25,-.4,.8,-.65);tracks.turn(4.25,4.75,.4,-.65,0);records=[];angles=[]
        for frame in range(1,97):
            scene.frame_set(frame);t=(frame-1)/12;yaw=90*smooth((t-1.75)/.5)*(1-smooth((t-4.25)/.5));position=Vector((-.4+.8*smooth((t-2.25)/2),-.65,0));drop=-.05*(1-smooth((t-7.25)/.75));feet={side:tracks.at(side,t) for side in ('L','R')}
            actor.pose(frame,position,yaw,drop,feet,{'R':(position+rotation(yaw) @ Vector((.30,-.03,.92)),rotation(yaw),rotation(yaw) @ Vector((1,-1,2))),'L':(self.hand(t,position,yaw,drop),rotation(yaw),rotation(yaw) @ Vector((-1,-1,3)))});records.append((frame,feet));angles.append((frame,yaw))
        hand=actor.arms['L'][2];scene.frame_set(10);bpy.context.view_layer.update();constraint=target.constraints.new('CHILD_OF');constraint.name='Lightek rigid palm grip';constraint.target=hand;constraint.inverse_matrix=hand.matrix_world.inverted()
        for frame in range(1,97):
            scene.frame_set(frame);target.location=Vector((-.83 if frame<67 else -.03,-.1,1.08));target.keyframe_insert(data_path='location',frame=frame)
            constraint.influence=1 if 10<=frame<67 else 0;constraint.keyframe_insert(data_path='influence',frame=frame)
        action=target.animation_data.action
        for curve in action.fcurves:
            for point in curve.keyframe_points:point.interpolation='CONSTANT'
        views_v1.bake(root,profile,angles);errors=[];ground=[];grip=[];support_errors=[];released=[]
        colliders=[row for row in self.objects if str(row['id']) in self.created and self.created[str(row['id'])]!=target and not row.get('definition',{}).get('character_profile') and row['type'] not in ('camera','area_light','point_light','sun_light','spot_light')]
        for frame,feet in records:
            scene.frame_set(frame);bpy.context.view_layer.update();a,b=actor.errors(feet);errors+=a;ground+=b
            if 10<=frame<67:grip.append(((hand.matrix_world @ Vector((0,.004,0)))-(target.matrix_world @ Vector((0,-1,1)))).length)
            if frame<13 or frame>=67:
                table=supports['pickup' if frame<13 else 'putdown'];bottom=target.matrix_world @ Vector((0,0,-1));top=table.matrix_world @ Vector((0,0,1));support_errors.append(abs(bottom.z-top.z))
            if frame>=67:released.append(target.matrix_world.translation.copy())
            depsgraph=bpy.context.evaluated_depsgraph_get();mesh=spatial_checks.geometry(target,depsgraph)
            for row in colliders:
                other=self.created[str(row['id'])];other_mesh=spatial_checks.geometry(other,depsgraph)
                if not mesh or not other_mesh or not spatial_checks.intersects(mesh,other_mesh):continue
                allowed=(other==supports['pickup'] and frame<=13) or (other==supports['putdown'] and frame>=67)
                if allowed:
                    top=(other.matrix_world @ Vector((0,0,1))).z;local=[other.matrix_world.inverted() @ vertex for vertex in mesh[0]]
                    if min(v.z for v in mesh[0])>=top-.002 and all(abs(v.x)<=1.0001 and abs(v.y)<=1.0001 for v in local):continue
                raise RuntimeError('Carried prop collision at frame '+str(frame)+': '+row['name'])
        drift=max((point-released[0]).length for point in released)
        if max(errors+ground+grip+support_errors+[drift])>.002:raise RuntimeError('Carry grip, support or release failed its 2 mm tolerance')
        root['lightek_mechanics_report']=json.dumps({'driver':'carry','version':1,'frames':96,'grip_frame':10,'release_frame':67,'max_limb_error':max(errors),'max_ground_error':max(ground),'max_grip_error':max(grip),'max_support_error':max(support_errors),'release_drift':drift})
        return {'actor_id':str(item['id']),'target_id':str(plan['target_object_id']),'contact_mesh':hand,'first':10,'last':67,'point':Vector((0,-1,1)),'normal':Vector((0,-1,0))}
