"""Continuous presentation mesh driven by immutable contact-solver transforms."""
import bpy,math,json
from mathutils import Vector,Matrix

def capsule_arrays(a,b,r,segments=16):
 a=Vector(a);b=Vector(b);Q=(b-a).to_track_quat('Z','Y').to_matrix();length=(b-a).length;center=(a+b)/2
 rings=[]
 for j in range(7):
  t=-math.pi/2+j*math.pi/12;rings.append((r*math.cos(t),-length/2+r*math.sin(t)))
 for j in range(7):
  t=j*math.pi/12;rings.append((r*math.cos(t),length/2+r*math.sin(t)))
 verts=[list(center+Q@Vector((rr*math.cos(k*2*math.pi/segments),rr*math.sin(k*2*math.pi/segments),z))) for rr,z in rings for k in range(segments)]
 faces=[(j*segments+k,j*segments+(k+1)%segments,(j+1)*segments+(k+1)%segments,(j+1)*segments+k) for j in range(len(rings)-1) for k in range(segments)]
 return verts,faces

def primitives(sample):
 parts={p['name']:p for p in sample['parts']};w=parts['wristR'];W=Vector(w['b']);knuckles=[Vector(parts[f'pad{f}_0']['b']) for f in range(4)]
 out=[{'name':'wrist_skin','a':w['a'],'b':w['b'],'r':.025}]
 # Metacarpal fan and thenar pad fill the previously missing palm volume.
 for f,K in enumerate(knuckles):out.append({'name':f'metacarpal{f}','a':list(W),'b':list(K),'r':.011})
 center=sum(knuckles,Vector())/4
 out.append({'name':'thenar','a':list(W.lerp(center,.28)),'b':parts['pad4_0']['b'],'r':.012})
 for f in range(5):
  for j in range(3):
   p=parts[f'pad{f}_{j}'];out.append({'name':p['name'],'a':p['a'],'b':p['b'],'r':p['r']*[1.,.98,.95][j]})
 return out

def refine_sleeve(o,length,mat):
 # A tapered open cuff replaces the capsule's bulbous distal end, inside the same envelope.
 rings=[];r=.036
 for j in range(7):
  t=-math.pi/2+j*math.pi/12;rings.append((r*math.cos(t),-length/2+r*math.sin(t)))
 for j in range(1,9):
  u=j/8;rings.append((r+(.027-r)*(u*u*(3-2*u)),-length/2+length*u))
 rings +=[(.024,-length/2+length),(.024,length/2-.006)]
 verts=[(rr*math.cos(k*math.pi/12),rr*math.sin(k*math.pi/12),z) for rr,z in rings for k in range(24)]
 faces=[(j*24+k,j*24+(k+1)%24,(j+1)*24+(k+1)%24,(j+1)*24+k) for j in range(len(rings)-1) for k in range(24)]
 mesh=bpy.data.meshes.new('Tapered sleeve cuff');mesh.from_pydata(verts,[],faces);mesh.update();o.data=mesh;o.data.materials.append(mat)
 for p in mesh.polygons:p.use_smooth=True

def finalize_surface(o,sample):
 import numpy as np
 if not o.get('surface_finalized',False):
  bpy.context.view_layer.objects.active=o
  mod=o.modifiers.new('Surface LOD','DECIMATE');mod.ratio=.30;mod.use_collapse_triangulate=True;bpy.ops.object.modifier_apply(modifier=mod.name)
  # Preserve the original solved contact envelope on the prop-facing skin.
  x=np.empty(len(o.data.vertices)*3);o.data.vertices.foreach_get('co',x);x=x.reshape(-1,3)
  near=np.linalg.norm(x-np.array(sample['ball']),axis=1)<.050
  candidates=x[near];best=np.full(len(candidates),np.inf);projected=candidates.copy()
  for p in sample['parts']:
   if not p['name'].startswith('pad'):continue
   a=np.array(p['a']);b=np.array(p['b']);d=b-a;t=np.clip((candidates-a)@d/np.dot(d,d),0,1);axis=a+t[:,None]*d;delta=candidates-axis;distance=np.linalg.norm(delta,axis=1);signed=distance-p['r'];take=signed<best
   projected[take]=axis[take]+delta[take]/np.maximum(distance[take,None],1e-15)*p['r'];best[take]=signed[take]
  ids=np.flatnonzero(near);outside=best>0;x[ids[outside]]=projected[outside]
  o.data.vertices.foreach_set('co',x.ravel());o.data.update();o['surface_finalized']=True
 remove_micro_islands(o)
 return len(o.data.vertices)

def remove_micro_islands(o):
 import bmesh
 bm=bmesh.new();bm.from_mesh(o.data);seen=set();groups=[]
 for v in bm.verts:
  if v in seen:continue
  group=[];stack=[v];seen.add(v)
  while stack:
   p=stack.pop();group.append(p)
   for edge in p.link_edges:
    q=edge.other_vert(p)
    if q not in seen:seen.add(q);stack.append(q)
  groups.append(group)
 removed=0
 for group in sorted(groups,key=len,reverse=True)[1:]:
  lo=Vector(tuple(min(v.co[j] for v in group) for j in range(3)));hi=Vector(tuple(max(v.co[j] for v in group) for j in range(3)))
  if len(group)>16 or (hi-lo).length>.004:raise RuntimeError('Disconnected anatomical geometry; refusing to remove it')
  removed+=len(group);bmesh.ops.delete(bm,geom=group,context='VERTS')
 if removed:bm.to_mesh(o.data);o.data.update()
 bm.free();return removed
