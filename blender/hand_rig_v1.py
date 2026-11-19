"""One reusable weighted hand. No mesh-per-frame visibility or surface-cache keys."""
import json,math
from pathlib import Path
import bpy,numpy as np
from mathutils import Vector,Matrix
from hand_surface_v1 import primitives,capsule_arrays,finalize_surface
PROFILE=Path(__file__).parent/'profiles/contact_biped_v1.json'

def part_matrix(p):
 return Matrix.LocRotScale(Vector(p['p']),Matrix(p['R']).to_quaternion(),Vector((1,1,1)))

def targets(sample):
 parts={p['name']:p for p in sample['parts']};result={}
 for name,p in parts.items():
  if name in ('ball','palm') or name.startswith('pad'):continue
  result['Part.'+name]=part_matrix(p)
 palm=sample['geoms']['palm'];R=Matrix(palm['R']);W=Vector(parts['wristR']['b']);K=Matrix(((0,1,0),(0,0,1),(1,0,0)))
 result['Palm']=Matrix.LocRotScale(W,(R@K).to_quaternion(),Vector((1,1,1)))
 K=Matrix(((1,0,0),(0,0,1),(0,-1,0)))
 for f in range(5):
  for j in range(3):
   p=parts[f'pad{f}_{j}'];result[f'Digit.{f}.{j}']=Matrix.LocRotScale(Vector(p['b']),(Matrix(p['R'])@K).to_quaternion(),Vector((1,1,1)))
 for side,e in zip(('L','R'),sample['eyes']):result['Eye.'+side]=Matrix.LocRotScale(Vector(e['o']),Vector(e['d']).to_track_quat('Y','Z'),Vector((1,1,1)))
 return result

def parents():
 result={'Palm':'Part.wristR','Eye.L':'Part.head','Eye.R':'Part.head'}
 for f in range(5):
  for j in range(3):result[f'Digit.{f}.{j}']='Palm' if j==0 else f'Digit.{f}.{j-1}'
 return result

def create_rig(sample):
 matrices=targets(sample);arm=bpy.data.armatures.new('ContactRig');rig=bpy.data.objects.new('ContactRig',arm);bpy.context.scene.collection.objects.link(rig);bpy.context.view_layer.objects.active=rig;rig.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
 for name,M in matrices.items():
  bone=arm.edit_bones.new(name);bone.head=M.translation;bone.tail=M.translation+M.to_3x3().col[1]*(.035 if name.startswith('Digit.') else .10);bone.align_roll(M.to_3x3().col[2]);bone.use_deform=True
 for name,parent in parents().items():arm.edit_bones[name].parent=arm.edit_bones[parent]
 bpy.ops.object.mode_set(mode='OBJECT');rig['contact_rig_profile']='contact_biped_v1'
 return rig

def apply_pose(rig,sample,frame=None):
 desired=targets(sample)
 for name,M in desired.items():
  p=rig.pose.bones[name];rest=p.bone.matrix_local
  if p.parent:
   parent=p.parent.name;basis=(rig.data.bones[parent].matrix_local.inverted()@rest).inverted()@desired[parent].inverted()@M
  else:basis=rest.inverted()@M
  p.rotation_mode='QUATERNION';p.location,p.rotation_quaternion,p.scale=basis.decompose()
  if frame is not None:
   for channel in ('location','rotation_quaternion','scale'):p.keyframe_insert(data_path=channel,frame=frame)
 bpy.context.view_layer.update()

def smooth(x):
 x=np.clip(x,0,1);return x*x*(3-2*x)

def skin_weights(mesh,sample):
 x=np.array([v.co[:] for v in mesh.vertices]);parts={p['name']:p for p in sample['parts']};sources=primitives(sample);signed=[]
 for p in sources:
  a=np.array(p['a']);b=np.array(p['b']);v=b-a;t=np.clip((x-a)@v/np.dot(v,v),0,1);signed.append(np.linalg.norm(x-a-t[:,None]*v,axis=1)-p['r'])
 owner=np.argmin(np.array(signed),axis=0);weights={'Palm':np.ones(len(x)),'Part.wristR':np.zeros(len(x))}
 for f in range(5):
  for j in range(3):weights[f'Digit.{f}.{j}']=np.zeros(len(x))
 for index,source in enumerate(sources):
  ids=np.flatnonzero(owner==index)
  if not len(ids):continue
  name=source['name']
  if name.startswith('pad'):
   f,j=map(int,name[3:].split('_'));p=parts[name];a=np.array(p['b']);v=np.array(p['a'])-a;t=(x[ids]-a)@v/np.dot(v,v)
   previous='Palm' if j==0 else f'Digit.{f}.{j-1}';current=f'Digit.{f}.{j}';w=smooth((t+.15)/.30)
   weights['Palm'][ids]=0;weights[previous][ids]+=1-w;weights[current][ids]+=w
   if j<2:
    nxt=smooth((t-.85)/.30);weights[current][ids]*=1-nxt;weights[f'Digit.{f}.{j+1}'][ids]+=w*nxt
  elif name.startswith('metacarpal') or name=='thenar':
   f=int(name[-1]) if name.startswith('metacarpal') else 4;p=parts[f'pad{f}_0'];a=np.array(p['b']);v=np.array(p['a'])-a;t=(x[ids]-a)@v/np.dot(v,v);distance=np.linalg.norm(x[ids]-a-np.clip(t,0,1)[:,None]*v,axis=1);w=smooth((t+.15)/.30)*(distance<.011)
   weights['Palm'][ids]=1-w;weights[f'Digit.{f}.0'][ids]=w
 w=parts['wristR'];a=np.array(w['a']);v=np.array(w['b'])-a;t=(x-a)@v/np.dot(v,v);wrist=smooth((1-t)/.4)*(owner==0)
 for name in list(weights):weights[name]*=1-wrist
 weights['Part.wristR']+=wrist
 total=sum(weights.values());return {name:value/total for name,value in weights.items()}

def create_hand(sample,material,rig):
 vertices=[];faces=[]
 for p in primitives(sample):
  v,fs=capsule_arrays(p['a'],p['b'],p['r']);offset=len(vertices);vertices+=v;faces += [tuple(i+offset for i in face) for face in fs]
 mesh=bpy.data.meshes.new('ContactHand');mesh.from_pydata(vertices,[],faces);mesh.update();hand=bpy.data.objects.new('ContactHand',mesh);bpy.context.scene.collection.objects.link(hand);hand.data.materials.append(material)
 bpy.ops.object.select_all(action='DESELECT');hand.select_set(True);bpy.context.view_layer.objects.active=hand;hand.data.remesh_voxel_size=.0012;hand.data.remesh_voxel_adaptivity=0;bpy.ops.object.voxel_remesh();mod=hand.modifiers.new('Tissue continuity','SMOOTH');mod.factor=.35;mod.iterations=2;bpy.ops.object.modifier_apply(modifier=mod.name);finalize_surface(hand,sample)
 for p in hand.data.polygons:p.use_smooth=True
 for name,values in skin_weights(hand.data,sample).items():
  group=hand.vertex_groups.new(name=name)
  for i,value in enumerate(values):
   if value>1e-8:group.add([i],float(value),'REPLACE')
 mod=hand.modifiers.new('Articulated hand skin','ARMATURE');mod.object=rig;mod.use_deform_preserve_volume=True;hand['contact_skin_version']=1
 return hand
