"""Bake a contact-driven, torque-limited hand and free load into editable Blender keys."""
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import tempfile
import bpy
import spatial_checks
from mathutils import Vector,Matrix,Quaternion
from bench_v1 import source,key_object
from biped_v2 import FootTracks,rotation
from biped_v3 import Biped

class GraspV1:
    requires_world=True
    target_tag='mechanics_grasp'
    target_type='sphere'
    phases={'reach':[0,1],'close':[1,2],'lift':[2,3],'hold':[3,4],'lower':[4,5],'open':[5,6],'withdraw':[6,8]}
    files=('grasp_v1.py','biped_v3.py','biped_v2.py','spatial_frame_v1.py','bench_v1.py','kinematics_v1.py','physics/grasp_v1.py','physics/human_v1.json')
    @classmethod
    def fingerprint(cls):return hashlib.sha256(b''.join((Path(__file__).parent/name).read_bytes() for name in cls.files)).hexdigest()
    def __init__(self,objects,created):self.objects=objects;self.created=created
    def capsule(self,name,radius,half):
        vertices=[];faces=[];rings=[];segments=12
        for cap in (-1,1):
            for i in range(5):
                angle=(-math.pi/2+i*math.pi/8) if cap==-1 else i*math.pi/8
                rings.append((radius*math.cos(angle),cap*half+radius*math.sin(angle)))
        for rad,z in rings:
            vertices.extend((rad*math.cos(j*2*math.pi/segments),rad*math.sin(j*2*math.pi/segments),z) for j in range(segments))
        for i in range(len(rings)-1):
            for j in range(segments):faces.append((i*segments+j,i*segments+(j+1)%segments,(i+1)*segments+(j+1)%segments,(i+1)*segments+j))
        mesh=bpy.data.meshes.new(name);mesh.from_pydata(vertices,[],faces);mesh.update()
        obj=bpy.data.objects.new(name,mesh);bpy.context.scene.collection.objects.link(obj)
        for face in mesh.polygons:face.use_smooth=True
        obj['lightek_capsule_radius_m']=radius;obj['lightek_capsule_half_length_m']=half
        return obj
    def bake(self,item,root,target):
        scene=bpy.context.scene;definition=item['definition'];plan=definition['mechanics_plan'];profile=definition['character_profile'];physics=json.loads((Path(__file__).parent/'physics/human_v1.json').read_text())
        if plan.get('driver_fingerprint')!=self.fingerprint() or plan.get('source_blob_id')!=profile.get('source_blob_id') or plan.get('phases')!=self.phases or plan.get('physical_profile')!=physics:
            raise RuntimeError('The pinned contact physics implementation or profile changed')
        if scene.frame_start!=1 or scene.frame_end!=96 or scene.render.fps!=12 or scene.render.fps_base!=1:raise RuntimeError('Grasp v1 requires eight seconds at 12 fps')
        if (target.location-Vector((-.83,-.24,1))).length>.00001 or (target.scale-Vector((.045,.045,.045))).length>.00001 or target.constraints:raise RuntimeError('Use the calibrated free sphere')
        indexed={str(row['id']):row for row in self.objects};support_ids=plan.get('support_object_ids',{})
        if set(support_ids)!={'grasp'}:raise RuntimeError('The contact study needs its frozen table')
        table=self.created.get(str(support_ids['grasp']));row=indexed.get(str(support_ids['grasp']))
        if not table or not row or row['type']!='cube' or row['definition'].get('mechanics_support')!='grasp' or any(row['definition'].get(k) for k in ('animation','story_relation','authoring_commands')) or (table.location-Vector((-.83,-.24,.905))).length>.00001 or (table.scale-Vector((.18,.20,.05))).length>.00001 or any(abs(v)>.00001 for v in table.rotation_euler):raise RuntimeError('Use the calibrated grasp table')
        python=os.environ.get('STUDIO_PHYSICS_PYTHON','/opt/lightek-physics/venv/bin/python')
        with tempfile.TemporaryDirectory(prefix='lightek-physics-') as folder:
            output=Path(folder)/'simulation.json'
            try:
                run=subprocess.run([python,str(Path(__file__).parent/'physics/grasp_v1.py'),'--output',str(output)],capture_output=True,text=True,timeout=30,check=True,env={**os.environ,'OMP_NUM_THREADS':'1','OPENBLAS_NUM_THREADS':'1','PYTHONDONTWRITEBYTECODE':'1'})
            except (OSError,subprocess.SubprocessError) as error:
                raise RuntimeError('The CPU contact physics runtime is unavailable. Rebuild the Studio media image with MuJoCo 3.3.7.') from error
            result=json.loads(output.read_text())
        frames=result['frames'];report=result['report']
        if report['solver_version']!='3.3.7' or len(frames)!=96 or report['max_penetration_m']>.002 or report['max_finger_torque_nm']>physics['finger_torque_limit_nm']+1e-8 or report['lift_m']<.13 or abs(report['settled_height_m']-.145)>.002:raise RuntimeError('Contact physics failed its lift, force, penetration or release checks')
        actor=Biped(root,profile['mechanics'],physics);tracks=FootTracks(-.4,-.65,0);offset=Vector((-.83,-.24,.855));hand=actor.arms['L'][2]
        # Replace the flat source drawing in this generated take only. Source Cast stays intact.
        material=hand.data.materials[0] if hand.data.materials else None
        for obj in list(root.children_recursive):
            if obj.get('lightek_source_object') in ('Hand L','Side Hand L'):
                obj.data=obj.data.copy();obj.data.clear_geometry()
        grip=bpy.data.objects.new('Articulated contact hand',None);scene.collection.objects.link(grip);grip.parent=root
        meshes={}
        for name,geometry in frames[0]['geoms'].items():
            if name=='palm':
                bpy.ops.mesh.primitive_cube_add(size=2);mesh=bpy.context.object;mesh.name='Contact palm';mesh.scale=Vector(geometry['size']);bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
            else:mesh=self.capsule('Contact '+name,geometry['size'][0],geometry['size'][1])
            mesh.parent=grip
            if material:mesh.data.materials.append(material)
            meshes[name]=mesh
        feet_records=[];wrist_errors=[];arm_torques=[]
        for record in frames:
            frame=record['frame'];scene.frame_set(frame);position=Vector((-.4,-.65,0));feet={side:tracks.at(side,record['time_s']) for side in ('L','R')}
            center=Vector(record['hand'])+offset;wrist=center+Vector((-.065,-.065,0))
            actor.pose(frame,position,0,-.04,feet,{'L':(wrist-Vector((0,0,.12)),rotation(0))})
            grip.location=root.matrix_world.inverted() @ center;key_object(grip,frame);bpy.context.view_layer.update()
            for name,geometry in record['geoms'].items():
                meshes[name].rotation_mode='QUATERNION';meshes[name].matrix_world=Matrix.LocRotScale(Vector(geometry['position'])+offset,Matrix(geometry['rotation']).to_quaternion(),Vector((1,1,1)));key_object(meshes[name],frame)
            target.rotation_mode='QUATERNION';target.location=Vector(record['ball'])+offset;target.rotation_quaternion=Quaternion(record['ball_quaternion']);key_object(target,frame)
            bpy.context.view_layer.update();wrist_errors.append(((actor.rig.matrix_world @ actor.arms['L'][1].tail)-wrist).length);feet_records.append((frame,feet))
            shoulder=actor.rig.matrix_world @ actor.arms['L'][0].head
            elbow=actor.rig.matrix_world @ actor.arms['L'][1].head
            # Gravity load estimate for inspection, not a claimed dynamic shoulder solver.
            g=physics['gravity_m_s2'];body_mass=physics['body_mass_kg'];fractions=physics['segment_mass_fractions']
            weighted=[((shoulder+elbow)/2,body_mass*fractions['upper_arm']),((elbow+wrist)/2,body_mass*fractions['forearm']),(center,body_mass*fractions['hand'])]
            if record['load_contacts']:weighted.append((target.location,physics['prop_mass_kg']))
            arm_torques.append(sum(((point-shoulder).cross(Vector((0,0,-mass*g))) for point,mass in weighted),Vector((0,0,0))).length)
        for obj in [target,grip,*meshes.values()]:
            obj['lightek_physics_profile']=physics['id']
            if obj.animation_data:
                for curve in obj.animation_data.action.fcurves:
                    for key in curve.keyframe_points:key.interpolation='LINEAR'
        report.update({'driver':'grasp','version':1,'frames':96,'max_wrist_error_m':max(wrist_errors),'min_elbow_flexion_deg':min(actor.elbow_angles),'max_elbow_flexion_deg':max(actor.elbow_angles),'max_shoulder_gravity_load_nm':max(arm_torques)})
        if report['max_wrist_error_m']>.002:raise RuntimeError('The anatomical wrist did not reach its physical hand')
        colliders=[row for row in self.objects if str(row['id']) in self.created and self.created[str(row['id'])]!=target and not row.get('definition',{}).get('character_profile') and row['type'] not in ('camera','area_light','point_light','sun_light','spot_light')]
        ground=[]
        for frame,feet in feet_records:
            scene.frame_set(frame);bpy.context.view_layer.update();errors,floors=actor.errors(feet);ground+=floors
            if max(errors+floors)>.002:raise RuntimeError('The calibrated grip study lost its grounded limbs')
            depsgraph=bpy.context.evaluated_depsgraph_get();load=spatial_checks.geometry(target,depsgraph)
            for row in colliders:
                other=self.created[str(row['id'])];obstacle=spatial_checks.geometry(other,depsgraph)
                if not load or not obstacle or not spatial_checks.intersects(load,obstacle):continue
                if other==table and min(vertex.z for vertex in load[0]) >= (table.matrix_world @ Vector((0,0,1))).z-.002:continue
                raise RuntimeError('Physical load collision at frame '+str(frame)+': '+row['name'])

        report['max_ground_error_m']=max(ground)
        root['lightek_mechanics_report']=json.dumps(report,allow_nan=False)
        text=bpy.data.texts.new('Lightek contact simulation.json');text.write(json.dumps(result,allow_nan=False))
        return [{'actor_id':str(item['id']),'target_id':str(plan['target_object_id']),'contact_mesh':grip,'first':1,'last':96,'physics_sphere_radius_m':physics['prop_radius_m'],'capsules':[mesh for name,mesh in meshes.items() if name!='palm']}, {'actor_id':str(item['id']),'target_id':str(support_ids['grasp']),'contact_mesh':grip,'first':1,'last':96,'point':Vector((0,0,1)),'normal':Vector((0,0,1))}]
