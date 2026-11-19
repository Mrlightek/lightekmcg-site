"""Validated pickup/inspect/return action for the contact_biped v1 source contract."""
import bpy,json,hashlib,os,subprocess,tempfile,base64
import numpy as np
from pathlib import Path
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
import hand_rig_v1 as hand
from bench_v1 import source
import spatial_checks

FILES=('grasp_v4.py','spatial_checks.py','bench_v1.py','hand_rig_v1.py','hand_surface_v1.py','contact_character_v1.py','profiles/contact_biped_v1.json','physics/pickup_v1/run.py','physics/pickup_v1/solve.py','physics/pickup_v1/feasible.py','physics/pickup_v1/planner.py','physics/pickup_v1/ik.py','physics/pickup_v1/ik_untracked.py','physics/pickup_v1/extended.py','physics/pickup_v1/clearance_checks.py','physics/grasp_v3.py','physics/human_v1.json','physics/pedestal_contact_v3.json')
PHASES={'commit':[0,.25],'reach_grip':[.25,1.85],'lift':[1.85,3.25],'assess':[3.25,4.5],'place_unload':[4.5,6.25],'recover':[6.25,8]}
PROFILE={'id':'contact_biped_v1','body_mass_kg':75,'prop_mass_kg':.2,'prop_radius_m':.045,'duration_s':8,'fps':24}
class GraspV4:
 requires_world=True;target_type='sphere';target_tag='mechanics_grasp';phases=PHASES;files=FILES
 @classmethod
 def fingerprint(cls):return hashlib.sha256(b''.join((Path(__file__).parent/n).read_bytes() for n in FILES)).hexdigest()
 def __init__(self,objects,created):self.objects=objects;self.created=created
 def bake(self,item,root,target):
  scene=bpy.context.scene;d=item['definition'];plan=d['mechanics_plan'];profile=d['character_profile']
  if plan.get('driver_fingerprint')!=self.fingerprint() or plan.get('source_blob_id')!=profile.get('source_blob_id') or plan.get('physical_profile')!=PROFILE or plan.get('phases')!=PHASES:raise RuntimeError('The pinned pickup action or source profile changed')
  if scene.render.fps!=24 or scene.frame_start!=1 or scene.frame_end!=192 or scene.render.fps_base!=1:raise RuntimeError('Pickup v4 requires exactly eight seconds at 24 fps')
  if root.matrix_world!=Matrix.Identity(4):raise RuntimeError('The calibrated performer must retain its unit source transform')
  if (target.location-Vector((.46,-.22,1))).length>1e-6 or (target.scale-Vector((.045,)*3)).length>1e-6 or target.constraints:raise RuntimeError('Choose the calibrated free 200 g sphere')
  support=self.created.get(str(plan.get('support_object_ids',{}).get('grasp')))
  if support is None or (support.location-Vector((.46,-.22,.905))).length>1e-6 or (support.scale-Vector((.18,.20,.05))).length>1e-6 or any(abs(v)>1e-6 for v in support.rotation_euler):raise RuntimeError('The calibrated static pedestal is missing')
  fixtures={'ball':('sphere',(.46,-.22,1),(.045,.045,.045)),'grasp':('cube',(.46,-.22,.905),(.18,.20,.05)),'grasp_pedestal':('cube',(.46,-.22,.4275),(.08,.10,.4275)),'ground':('plane',(0,0,0),(4,4,1))}
  for row in self.objects:
   if row.get('type') in ('camera','area_light','point_light','sun_light','spot_light'):continue
   if row.get('definition',{}).get('character_profile'):
    if str(row['id'])!=str(item['id']):raise RuntimeError('Pickup v4 supports one calibrated performer')
    continue
   tag=row.get('definition',{}).get('template_source_object_id');expected=fixtures.get(tag);o=self.created.get(str(row['id']))
   if not expected or o is None or row['type']!=expected[0] or (o.location-Vector(expected[1])).length>1e-6 or (o.scale-Vector(expected[2])).length>1e-6 or any(abs(v)>1e-6 for v in o.rotation_euler) or o.constraints or o.animation_data:raise RuntimeError('The calibrated pickup environment changed; prepare a new supported action')
  rig=source(root,'ContactRig');skin=source(root,'ContactHand')
  if any(skin.vertex_groups[g.group].name not in rig.data.bones for v in skin.data.vertices for g in v.groups):raise RuntimeError('Hand weights reference an unknown bone')
  if rig.type!='ARMATURE' or skin.type!='MESH' or not any(m.type=='ARMATURE' and m.object==rig and m.use_deform_preserve_volume for m in skin.modifiers):raise RuntimeError('Bind one weighted ContactHand to ContactRig')
  rest=json.loads(hand.PROFILE.read_text())['rest']
  for obj in root.children_recursive:
   if obj.constraints or (obj.animation_data and obj.animation_data.drivers):raise RuntimeError('Use a source with no competing constraints or drivers')
   if obj.type=='MESH' and any(m.type!='ARMATURE' or m.object!=rig for m in obj.modifiers):raise RuntimeError('The calibrated source permits only its armature modifier')
   keys=getattr(obj.data,'shape_keys',None)
   if keys and keys.animation_data and keys.animation_data.drivers:raise RuntimeError('Camera-dependent shape drivers are not supported')
  for name,M in hand.targets(rest).items():
   bone=rig.data.bones.get(name)
   if bone is None or max(abs(bone.matrix_local[i][j]-M[i][j]) for i in range(4) for j in range(4))>2e-6:raise RuntimeError('The contact rig bind calibration changed')
  for vertex in skin.data.vertices:
   if abs(sum(g.weight for g in vertex.groups)-1)>1e-5:raise RuntimeError('Every hand vertex needs normalized rig weights')
  python=os.environ.get('STUDIO_PHYSICS_PYTHON','/opt/lightek-physics/venv/bin/python')
  with tempfile.TemporaryDirectory(prefix='pickup-physics-') as folder:
   path=Path(folder)/'result.json'
   try:subprocess.run([python,str(Path(__file__).parent/'physics/pickup_v1/run.py'),'--output',str(path)],capture_output=True,text=True,check=True,timeout=180,env={**os.environ,'OMP_NUM_THREADS':'1','OPENBLAS_NUM_THREADS':'1','PYTHONDONTWRITEBYTECODE':'1'})
   except (OSError,subprocess.SubprocessError) as e:raise RuntimeError('Pickup physics is unavailable or rejected. Install the pinned CPU physics runtime; no attachment fallback is allowed.') from e
   data=json.loads(path.read_text())
   if not data['report'].get('simulation_checks_passed') or not all(data['report'].get('checks',{}).values()):raise RuntimeError('Pickup physics rejected: '+json.dumps(data['report']))
   compressed=path.with_suffix('.json.gz').read_bytes()
  report=data['report']
  if not report.get('simulation_checks_passed') or not all(report['checks'].values()):raise RuntimeError('Pickup physics did not pass all required checks')
  for sample in data['frames']:
   hand.apply_pose(rig,sample,sample['frame']);target.rotation_mode='QUATERNION';target.location=sample['ball'];target.rotation_quaternion=sample['ball_quat'];target.keyframe_insert(data_path='location',frame=sample['frame']);target.keyframe_insert(data_path='rotation_quaternion',frame=sample['frame'])
  for obj in [rig,target]:
   if obj.animation_data:
    for curve in obj.animation_data.action.fcurves:
     for key in curve.keyframe_points:key.interpolation='LINEAR'
  max_depth=0.;table_hits=0;eye_error=0.;camera_errors=0;rig_error=0.;skin_body_hits=0;skin_floor_min=float('inf')
  body=[o for o in root.children_recursive if o.type=='MESH' and o.get('contact_part') not in (None,'foreR','wristR')]
  if len(body)!=len([p for p in rest['parts'] if p['name'] not in ('ball','palm','foreR','wristR') and not p['name'].startswith('pad')]):raise RuntimeError('The calibrated body geometry changed')
  cameras=[o for o in scene.objects if o.type=='CAMERA'];oldcam=scene.camera
  for sample in data['frames']:
   scene.frame_set(sample['frame']);bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get();geometry=spatial_checks.geometry(skin,dg);tree=BVHTree.FromPolygons(geometry[0],geometry[1],all_triangles=True);near=tree.find_nearest(target.matrix_world.translation)
   if near[0] is None or (target.matrix_world.translation-near[0]).dot(near[1])<0:raise RuntimeError('The load is enclosed by invalid hand skin: '+json.dumps({'frame':sample['frame'],'distance':near[3],'normal_dot':(target.matrix_world.translation-near[0]).dot(near[1]) if near[0] else None}))
   rig_error=max(rig_error,max(abs(rig.pose.bones[n].matrix[i][j]-M[i][j]) for n,M in hand.targets(sample).items() for i in range(4) for j in range(4)))
   skin_floor_min=min(skin_floor_min,min(v.z for v in geometry[0]))
   for part in body:
    surface=spatial_checks.geometry(part,dg);skin_body_hits+=len(tree.overlap(BVHTree.FromPolygons(surface[0],surface[1],all_triangles=False)))
   column=self.created[next(str(row['id']) for row in self.objects if row.get('definition',{}).get('template_source_object_id')=='grasp_pedestal')];surface=spatial_checks.geometry(column,dg);table_hits+=len(tree.overlap(BVHTree.FromPolygons(surface[0],surface[1],all_triangles=False)))
   max_depth=max(max_depth,max(0,.045-near[3]));plate=spatial_checks.geometry(support,dg);table_hits+=len(tree.overlap(BVHTree.FromPolygons(plate[0],plate[1],all_triangles=False)))
   for side,e in zip(('L','R'),sample['eyes']):
    pupil=source(root,'Pupil '+side);evaluated=pupil.evaluated_get(dg);mesh=evaluated.to_mesh()
    try:direction=(evaluated.matrix_world.to_3x3().inverted().transposed()@sum((p.normal*p.area for p in mesh.polygons),Vector())).normalized();eye_error=max(eye_error,direction.angle(Vector(e['d'])))
    finally:evaluated.to_mesh_clear()
   def state_signature():
    rows=[]
    for obj in [root,*root.children_recursive]:
     evaluated=obj.evaluated_get(bpy.context.evaluated_depsgraph_get());rows.extend(v for row in evaluated.matrix_world for v in row)
     if evaluated.type=='ARMATURE':
      for bone in evaluated.pose.bones:rows.extend(v for row in bone.matrix for v in row)
     rows.extend((obj.hide_render,obj.hide_viewport))
    return np.asarray(rows,dtype=np.float32).tobytes()
   baseline=state_signature()
   for camera in cameras:
    scene.camera=camera;bpy.context.view_layer.update();camera_errors+=state_signature()!=baseline
  scene.camera=oldcam
  checks={'render_mesh_to_physics_geometry_consistency':rig_error<2e-6,'weighted_skin_body_clearance':skin_body_hits==0,'weighted_skin_floor_clearance':skin_floor_min>0,'weighted_skin_contact':max_depth<=.002,'weighted_skin_pedestal_clearance':table_hits==0,'calibrated_eye_mesh_ray_alignment':eye_error<=.0349066,'shared_world_state_across_render_cameras':camera_errors==0,'single_weighted_hand':len([o for o in root.children_recursive if o.get('contact_skin_version')==1])==1}
  report['checks'].update(checks);report.update(accepted=all(report['checks'].values()),simulation_checks_passed=bool(report['simulation_checks_passed']),required_checks_pending=[],driver='grasp',version=4,rig_transform_error=rig_error,weighted_skin_body_intersections=skin_body_hits,weighted_skin_min_floor_m=skin_floor_min,weighted_skin_max_ball_depth_m=max_depth,weighted_skin_table_intersections=table_hits,eye_ray_error_rad=eye_error,driver_fingerprint=plan['driver_fingerprint'],physical_profile=PROFILE,simulation_sha256=data['simulation_sha256'])
  if not report['accepted']:raise RuntimeError('Pickup render gate rejected: '+json.dumps(report))
  root['lightek_mechanics_report']=json.dumps(report);text=bpy.data.texts.new('Lightek pickup validation.json');text.write(json.dumps(report));raw=bpy.data.texts.new('Lightek pickup simulation.json.gz.base64');encoded=base64.b64encode(compressed).decode();raw.write('\n'.join(encoded[i:i+120] for i in range(0,len(encoded),120)))
  scene.frame_set(1)
  return [{'actor_id':str(item['id']),'target_id':str(plan['target_object_id']),'contact_mesh':skin,'first':1,'last':192,'physics_sphere_radius_m':.045,'physics_skin':True},{'actor_id':str(item['id']),'target_id':str(plan['support_object_ids']['grasp']),'contact_mesh':skin,'first':1,'last':192,'point':Vector((0,0,1)),'normal':Vector((0,0,1))}]
