"""Direction-aware side approach, turn and seated performance; v1 stays immutable."""
import json,hashlib
from pathlib import Path
import bpy
from mathutils import Vector
from bench_v1 import smooth,source,BenchV1
from biped_v2 import Biped,FootTracks,rotation
import views_v1

class BenchV2:
    phases=BenchV1.phases
    files=('bench_v2.py','biped_v2.py','views_v1.py','spatial_frame_v1.py','bench_v1.py','kinematics_v1.py')
    @classmethod
    def fingerprint(cls):return hashlib.sha256(b''.join((Path(__file__).parent/name).read_bytes() for name in cls.files)).hexdigest()
    def bake(self,item,root,target):
        scene=bpy.context.scene;definition=item['definition'];plan=definition['mechanics_plan'];profile=definition['character_profile']
        if plan.get('driver_fingerprint')!=self.fingerprint() or plan.get('source_blob_id')!=profile.get('source_blob_id') or plan.get('phases')!=self.phases:raise RuntimeError('The pinned mechanics implementation changed; prepare a reviewed new performance')
        if scene.frame_start!=1 or scene.frame_end!=96 or scene.render.fps!=12 or scene.render.fps_base!=1:raise RuntimeError('Bench v2 needs eight seconds at 12 fps')
        if (target.location-Vector((0,.27,.40))).length>.00001 or (target.scale-Vector((.8,.19,.04))).length>.00001 or any(abs(v)>.00001 for v in target.rotation_euler):raise RuntimeError('Use the calibrated static bench')
        actor=Biped(root,profile['mechanics']);support=source(root,profile['mechanics']['support']);tracks=FootTracks(-.8,-.24,90);tracks.walk(0,2,-.8,.8,-.24);tracks.turn(2,2.5,0,-.24,0);records=[];angles=[]
        for frame in range(1,97):
            scene.frame_set(frame);t=(frame-1)/12;sit=smooth((t-2.5)/.75)*(1-smooth((t-6.4)/.85));drop=(-.05*(1-sit)-.2568*sit)*(1-smooth((t-7.25)/.75));yaw=90*(1-smooth((t-2)/.5));position=Vector((-.8+.8*smooth(t/2),-.24+.46*sit,0))
            feet={side:tracks.at(side,t) for side in ('L','R')};q=rotation(yaw);hands={}
            for side,sign in (('L',-1),('R',1)):
                rest=position+q @ Vector((sign*.43,-.01,.72+drop));hands[side]=(rest.lerp(Vector((sign*.30,-.10,.68)),sit),q)
            actor.pose(frame,position,yaw,drop,feet,hands);records.append((frame,feet,3.25<=t<=6.4));angles.append((frame,yaw))
        views_v1.bake(root,profile,angles);errors=[];ground=[];seats=[]
        for frame,feet,seated in records:
            scene.frame_set(frame);bpy.context.view_layer.update();a,b=actor.errors(feet);errors+=a;ground+=b
            if seated:seats.append(abs((support.matrix_world @ Vector((0,.004,-.0832))).z-(target.matrix_world @ Vector((0,0,1))).z))
        if max(errors+ground+seats)>.002:raise RuntimeError('Direction-aware biped support failed its tolerance')
        root['lightek_mechanics_report']=json.dumps({'driver':'bench','version':2,'frames':96,'max_limb_error':max(errors),'max_seat_error':max(seats),'max_ground_error':max(ground),'support_frames':len(seats),'walk_yaw':90,'seat_yaw':0})
        return {'actor_id':str(item['id']),'target_id':str(plan['target_object_id']),'contact_mesh':support,'first':40,'last':77,'point':Vector((0,0,1)),'normal':Vector((0,0,1))}
