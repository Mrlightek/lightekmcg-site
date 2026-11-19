"""Original calibrated adult source asset with a reusable skin and editable rig."""
import bpy,json,math
from pathlib import Path
from mathutils import Vector,Matrix
import hand_rig_v1 as hand
from hand_surface_v1 import capsule_arrays,refine_sleeve

def material(name,color):
 m=bpy.data.materials.new(name);m.diffuse_color=tuple(int(color[i:i+2],16)/255 for i in (1,3,5))+(1,);m.use_nodes=True;m.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=m.diffuse_color;return m

def mesh_object(name,vertices,faces,mat):
 data=bpy.data.meshes.new(name);data.from_pydata(vertices,[],faces);data.update();obj=bpy.data.objects.new(name,data);bpy.context.scene.collection.objects.link(obj);obj.data.materials.append(mat)
 for p in data.polygons:p.use_smooth=True
 return obj

def bind(obj,rig,bone):
 group=obj.vertex_groups.new(name=bone);group.add(list(range(len(obj.data.vertices))),1,'REPLACE');mod=obj.modifiers.new('Character rig','ARMATURE');mod.object=rig;mod.use_deform_preserve_volume=True

def sphere(name,r,mat,M):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=16,radius=r);o=bpy.context.object;o.name=name;o.data.materials.append(mat);o.data.transform(M)
 for p in o.data.polygons:p.use_smooth=True
 return o

def cube(name,half,mat,M):
 bpy.ops.mesh.primitive_cube_add(size=2);o=bpy.context.object;o.name=name;o.data.materials.append(mat);o.data.transform(M@Matrix.Diagonal((*half,1)));return o

def build(params):
 bpy.ops.wm.read_factory_settings(use_empty=True);scene=bpy.context.scene;scene.name='Lightek Performer';scene.render.fps=24
 sample=json.loads(hand.PROFILE.read_text())['rest'];rig=hand.create_rig(sample)
 skin=material('Skin',params.get('skin','#925e43'));jacket=material('Jacket',params.get('wardrobe','#344e78'));navy=material('Trousers','#19212f');dark=material('Mouth and pupils','#170e12');white=material('Eye white','#eeeadd');hair=material('Hair',params.get('hair','#211916'))
 objects={}
 for p in sample['parts']:
  name=p['name']
  if name in ('ball','palm','wristR') or name.startswith('pad'):continue
  cloth=name not in ('head','handL');r=p['r']+(.003 if cloth else 0);mat=skin if name.startswith('wrist') or name in ('head','handL') else navy if name.startswith(('foot','pelvis','thigh','shank')) else jacket
  if name=='head':
   o=sphere('Physical head',p['r'],skin,Matrix.Identity(4));o.data.materials.append(hair)
   for face in o.data.polygons:
    if face.center.z>.06:face.material_index=1
   # Calibrated eye sockets are part of the source, not camera-dependent overlays.
   for side in [-1,1]:
    bpy.ops.mesh.primitive_cylinder_add(vertices=24,radius=.020,depth=.18,location=(.15,side*.042,0),rotation=(0,math.pi/2,0));cut=bpy.context.object;bpy.context.view_layer.objects.active=o;mod=o.modifiers.new('Eye socket','BOOLEAN');mod.operation='DIFFERENCE';mod.object=cut;bpy.ops.object.modifier_apply(modifier=mod.name);bpy.data.objects.remove(cut,do_unlink=True)
   o.data.transform(hand.part_matrix(p))
  elif name.startswith('foot'):o=cube(name,(.13,.05,.04),mat,hand.part_matrix(p))
  else:
   v,f=capsule_arrays(p['a'],p['b'],r);o=mesh_object(name,v,f,mat)
   if name=='foreR':
    # Sleeve helper is defined in local axial coordinates before applying its bind transform.
    refine_sleeve(o,(Vector(p['b'])-Vector(p['a'])).length,mat);o.data.transform(hand.part_matrix(p))
  o['contact_part']=name;bind(o,rig,'Part.'+name);objects[name]=o
 mesh=hand.create_hand(sample,skin,rig);objects['hand']=mesh
 # Whites and pupils retain independent eye-ray controls on the same rig.
 eye_parts=[]
 for side,e in zip(('L','R'),sample['eyes']):
  o=sphere('White '+side,.0155,white,Matrix.Translation(Vector(e['o'])));bind(o,rig,'Part.head');eye_parts.append(o)
  radius=.0156;theta=math.asin(.006/radius);verts=[(0,0,radius)]
  for ring in range(1,5):
   a=theta*ring/4
   for k in range(24):verts.append((radius*math.sin(a)*math.cos(k*math.tau/24),radius*math.sin(a)*math.sin(k*math.tau/24),radius*math.cos(a)))
  faces=[(0,1+k,1+(k+1)%24) for k in range(24)]
  for ring in range(3):
   for k in range(24):faces.append((1+ring*24+k,1+(ring+1)*24+k,1+(ring+1)*24+(k+1)%24,1+ring*24+(k+1)%24))
  M=Matrix.LocRotScale(Vector(e['o']),Vector(e['d']).to_track_quat('Z','Y'),Vector((1,1,1)));o=mesh_object('Pupil '+side,[list(M@Vector(v)) for v in verts],faces,dark);bind(o,rig,'Eye.'+side)
 # Real editable face controls keep this source compatible with Cast registration.
 bpy.ops.object.select_all(action='DESELECT')
 for o in eye_parts:o.select_set(True)
 bpy.context.view_layer.objects.active=eye_parts[0];bpy.ops.object.join();eyes=bpy.context.object;eyes.name='FaceEyes';eyes.shape_key_add(name='Basis');eyes.shape_key_add(name='blink')
 head=next(p for p in sample['parts'] if p['name']=='head');M=hand.part_matrix(head)
 for name,z,controls in [('FaceMouth',-.04,['jaw_open','smile','mouth_wide','mouth_round',*['viseme_'+s for s in 'abcdefghx']]),('FaceBrows',.03,['brow_raise'])]:
  verts=[list(M@Vector((.106,.022*math.cos(k*math.tau/24),z+.003*math.sin(k*math.tau/24)))) for k in range(24)];o=mesh_object(name,verts,[tuple(range(24))],dark);bind(o,rig,'Part.head');o.shape_key_add(name='Basis')
  for key in controls:
   shape=o.shape_key_add(name=key)
   for point in shape.data:point.co+=M.to_3x3()@Vector((0,0,-.004 if key=='jaw_open' else .001))
 rig['contact_profile']='contact_biped_v1';scene['contact_profile']='contact_biped_v1';scene.frame_set(1)
 return rig,objects
