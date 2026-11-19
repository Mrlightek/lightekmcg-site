import sys,math,json,re
from pathlib import Path
import numpy as np
import mujoco
from ik_untracked import constrained_elbow
from planner import Plan
_reach_plan=None;_withdraw_plan=None
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import grasp_v3 as old
P=json.loads(old.PROFILE.read_text());DT=.001;OFF=np.array([.46,-.22,.855]);L1=.30;L2=.26;MOUNT=np.array([-.055,-.065,0.]);LE=np.hypot(L2+.055,.065);P['timestep_s']=DT
def ease(u):u=np.clip(u,0,1);return u*u*u*(10-15*u+6*u*u)
def easeD(u):
 u=float(np.clip(u,0,1));return 30*u*u*(1-u)*(1-u)
def lerp(a,b,u):return np.array(a)+(np.array(b)-a)*ease(u)
def body(t):
 c=ease(t/1.2)*(1-ease((t-6.3)/1.3));breath=.0012*math.sin(2*math.pi*t/2.7+.2*math.sin(t*1.1))
 return np.array([.006*c,.001*math.sin(t),-.012*c+breath])
def desired(t,stage,release_t=None,land_z=0,origin=None):
 rest=np.array([.10,-.22,.79])
 if t<.25:return rest
 if t<.55:return lerp(rest,[.13,-.50,.94],(t-.25)/.30)
 if t<.85:return lerp([.13,-.50,.94],[.33,-.50,1.10],(t-.55)/.30)
 if t<1.15:return lerp([.33,-.50,1.10],[.46,-.22,1.13],(t-.85)/.30)
 if t<1.40:return lerp([.46,-.22,1.13],[.46,-.22,1.04],(t-1.15)/.25)
 if t<1.85:return np.array([.46,-.22,1.04])
 if t<2.15:return np.array([.46,-.22,1.04+.003*ease((t-1.85)/.30)])
 if t<3.25:return np.array([.46,-.22,1.043+.147*ease((t-2.15)/1.10)])
 if t<4.50:
  u=(t-3.25)/1.25;return np.array([.46+.0012*math.sin(2.4*u),-.22+.0004*math.sin(4*u),1.19+.0010*math.sin(3.6*u)])
 if t<5.25:return lerp([.46+.0012*math.sin(2.4),-.22+.0004*math.sin(4),1.19+.001*math.sin(3.6)],[.46,-.22,1.042],(t-4.5)/.75)
 if stage in ('landing','confirm','release'):
  return np.array([.46,-.22,1.042-.002*ease((min(t,5.55)-5.25)/.30)-land_z])
 if stage=='withdraw':
  u=t-release_t;start=origin if origin is not None else np.array([.46,-.22,1.04-land_z])
  if u<.18:return lerp(start,[.46,-.22,1.15],u/.18)
  if u<.46:return lerp([.46,-.22,1.15],[.44,-.50,1.15],(u-.18)/.28)
  if u<.76:return lerp([.44,-.50,1.15],[.12,-.50,1.15],(u-.46)/.30)
  return lerp([.12,-.50,1.15],rest,(u-.76)/max(.3,7.85-release_t-.76))


 return np.array([.46,-.22,1.04-land_z])
def pose(C,t):
 S=np.array([0.,-.20,1.40])+body(t);v=C-S;dist=np.linalg.norm(v);axis=v/dist
 if not abs(L1-LE)<dist<L1+LE:raise ValueError(('reach',t,dist))
 E=_reach_plan.elbow(C,t) if _reach_plan is not None and t<=1.15 else _withdraw_plan.elbow(C,t) if _withdraw_plan is not None and t>=_withdraw_plan.t0 else constrained_elbow(S,C,L1,LE)
 v=(C-E)/LE;n=np.array([-.5,0.,-1.]);n-=v*np.dot(n,v);n/=np.linalg.norm(n)
 a=math.atan2(.065,L2+.055);d=math.cos(a)*v-math.sin(a)*n;n=math.sin(a)*v+math.cos(a)*n
 R=np.column_stack([d,n,np.cross(d,n)]);W=C+R@MOUNT
 return S,E,W,R
def euler(R):return np.array([math.atan2(-R[1,2],R[2,2]),math.asin(np.clip(R[0,2],-1,1)),math.atan2(-R[0,1],R[0,0])])
def build():
 xml,goals=old.model(P)
 xml=xml.replace('name="floor" type="plane"','name="floor" pos="0 0 -.855" type="plane"')
 xml=xml.replace('pos="-.02 -.065 0" size=".045 .008 .045"','pos="-.02 -.065 0" size=".035 .008 .030"')
 xml=xml.replace('kp="3.0" kv="0.08" forcerange="-0.35 0.35"','kp=".5" kv=".015" forcerange="-.08 .08"')
 axes=['1 0 0','0 1 0','0 0 1']
 xml=xml.replace('<geom name="palm"','<joint name="hand_rotation" type="ball" limited="false" damping=".02"/><geom name="palm"')
 acts=''.join(f'<general joint="hand_rotation" gear="{axis}" ctrllimited="true" ctrlrange="-3 3"/>' for axis in axes)
 xml=xml.replace('</actuator>',acts+'</actuator>').replace('kp="3000" kv="50"','kp="5000" kv="100"')
 xml=re.sub(r'<position joint="hand_z"[^>]*/>', '<general joint="hand_z" ctrllimited="true" ctrlrange="-150 150"/>',xml)
 xml=xml.replace('<joint damping=".03"','<joint damping=".01"').replace('solref=".01 1"','solref=".008 1"').replace('solimp=".95 .99 .001"','solimp=".99 .999 .001"')
 xml=xml.replace('iterations="100" noslip_iterations="5"','iterations="200" noslip_iterations="20" tolerance="1e-12"')
 return xml,goals

def simulate():
 global _reach_plan,_withdraw_plan
 _withdraw_plan=None
 _reach_plan=Plan(0,1.15,lambda t:desired(t,'approach'),lambda t:np.array([0.,-.20,1.40])+body(t),L1,LE,end_locked=True)
 xml,goals=build();m=mujoco.MjModel.from_xml_string(xml);d=mujoco.MjData(m)
 C=desired(0,'approach');S,E,W,R=pose(C,0);xyz=C-OFF-[0,0,.145];ang=euler(R)
 for a,v in zip('xyz',xyz):d.qpos[m.joint('hand_'+a).qposadr[0]]=v
 q=np.zeros(4);mujoco.mju_mat2Quat(q,R.reshape(-1));adr=m.joint('hand_rotation').qposadr[0];d.qpos[adr:adr+4]=q
 home=np.tile([0.,.35,.65],5);home[12]=1.0
 for f in range(5):
  for j in range(3):d.qpos[m.joint(f'joint{f}_{j}').qposadr[0]]=home[f*3+j]
 d.ctrl[:15]=home;d.ctrl[15:17]=xyz[:2];d.ctrl[17]=0;d.ctrl[18:]=0;mujoco.mj_forward(m,d)
 alpha=.98;filtered=0.;stage='approach';stable=0;stable_since=None;release_t=None;withdraw_t=None;land_z=0.;rows=[];events=[];prevN=0.;last_ang=ang;offset_z=.04;withdraw_origin=None;release_origin=None;footprint_gate=None;surface_t=None;surface_hand_z=None;force_offset=0.;filtered_up=0.;prev_ball_acc=0.;lift_baseline=None
 for k in range(round(8/DT)+1):
  t=k*DT
  if t>=1.25 and t<5.25:stage='grip' if t<1.85 else 'lift' if t<3.25 else 'hold' if t<4.5 else 'lower'
  if t>=5.25 and release_t is None:stage='landing'
  C=desired(t,stage,withdraw_t,land_z,withdraw_origin)
  if t>=1.40 and withdraw_t is None:
   if lift_baseline is None and t>=1.85:lift_baseline=max(1.,float(d.xpos[m.body('ball').id][2]+OFF[2]))
   if t<1.85:ball_target=1.0
   elif t<1.95:ball_target=lift_baseline+.0002*ease((t-1.85)/.10)
   elif t<3.25:ball_target=lift_baseline+.0002+(1.15-lift_baseline-.0002)*ease((t-1.95)/1.30)
   elif t<4.5:ball_target=1.15+.001*math.sin(3.6*(t-3.25)/1.25)
   elif t<5.0:ball_target=1.15-.146*ease((t-4.5)/.50)
   else:ball_target=1.004-.0046*ease((min(t,6.0)-5.0)/1.0)
   if prevN>1 and surface_t is None:
    actual_offset=d.xpos[m.body('hand').id][2]-d.xpos[m.body('ball').id][2]
    offset_z+=DT/(.060+DT)*(actual_offset-offset_z)
   if t<1.85:vref=0.
   elif t<1.95:vref=.0002/.10*easeD((t-1.85)/.10)
   elif t<3.25:vref=(1.15-lift_baseline-.0002)/1.30*easeD((t-1.95)/1.30)
   elif t<4.5:vref=.001*3.6/1.25*math.cos(3.6*(t-3.25)/1.25)
   elif t<5:vref=-.146/.5*easeD((t-4.5)/.5)
   else:vref=-.0046*easeD((min(t,6)-5))
   C[2]=ball_target+offset_z+.020*(vref-d.qvel[m.joint(0).dofadr[0]+2])
   if surface_t is not None:C[2]=d.xpos[m.body('hand').id][2]+OFF[2]
   if release_t is not None:C[2]=release_origin[2]+.030*ease((t-release_t)/.45)
  if withdraw_t is not None and t-withdraw_t>=.76 and footprint_gate is None:
   bounds=[]
   for name in ['palm']+[f'pad{f}_{j}' for f in range(5) for j in range(3)]:
    gid=m.geom(name).id;p=d.geom_xpos[gid]+OFF;Q=d.geom_xmat[gid].reshape(3,3);size=m.geom(gid).size
    extent=np.abs(Q)@size if name=='palm' else np.abs(Q[:,2])*size[1]+size[0]
    bounds.append([p-extent,p+extent])
   minimum=np.min(np.array(bounds)[:,0],axis=0);maximum=np.max(np.array(bounds)[:,1],axis=0)
   outside=maximum[0]<=.275 or minimum[0]>=.645 or maximum[1]<=-.425 or minimum[1]>=-.015
   if not outside or minimum[2]<.960:raise ValueError(('Footprint clearance gate blocked',t,minimum.tolist(),maximum.tolist()))
   footprint_gate=t;events.append({'event':'footprint_clear_gate','t':t,'hand_min':minimum.tolist(),'hand_max':maximum.tolist()})
  S,E,W,R=pose(C,t);xyz=C-OFF-[0,0,.145];ang=euler(R)
  ang=last_ang+(ang-last_ang+math.pi)%(2*math.pi)-math.pi;last_ang=ang
  if t>=1.25 and release_t is None and filtered>.05 and surface_t is None:
   normal_target=5.5 if surface_t is None else 5.5-4.5*ease((t-surface_t)/.15)
   gain=.03 if surface_t is None else .15
   rate=.10 if surface_t is None else 1.0
   alpha=np.clip(alpha+DT*np.clip(gain*(normal_target-filtered),-rate,rate),.60,1.06)
  for f in range(5):
   q=ease((t-(1.10+.025*f))/.40)
   if release_t is not None:q*=1-ease((t-release_t-.03*f)/.42)
   d.ctrl[f*3:f*3+3]=home[f*3:f*3+3]+q*(goals[f*3:f*3+3]*alpha-home[f*3:f*3+3])
  d.ctrl[15:17]=xyz[:2]
  zad=m.joint('hand_z').qposadr[0];zvd=m.joint('hand_z').dofadr[0]
  zforce=5000*(xyz[2]-d.qpos[zad])-100*d.qvel[zvd]
  if surface_t is not None and withdraw_t is None and release_t is None:
   blend=ease((t-surface_t)/.20)
   zforce=(1-blend)*zforce+blend*(.45*9.80665-80*d.qvel[zvd]-8*filtered_up)
  if 1.85<=t<3.25 and surface_t is None:
   zforce=min(zforce,.65*(9.80665+.50))
   zforce-=.25*max(0,prev_ball_acc-.75)
  d.ctrl[17]=np.clip(zforce,-150,150)
  bid=m.body('hand').id;actualR=d.xmat[bid].reshape(3,3);err=actualR.T@R
  angle=math.acos(np.clip((np.trace(err)-1)/2,-1,1));axis=np.array([err[2,1]-err[1,2],err[0,2]-err[2,0],err[1,0]-err[0,1]])
  error=axis*.5 if angle<1e-6 else axis*(angle/(2*math.sin(angle)))
  vad=m.joint('hand_rotation').dofadr[0];torque=80*error-.50*d.qvel[vad:vad+3]
  torque*=min(1,3/max(np.linalg.norm(torque),1e-12));d.ctrl[18:]=torque
  if k>0:mujoco.mj_step(m,d)
  mujoco.mj_forward(m,d)
  N=0.;up=0.;table=0.;contact_other=0.;pen=0.;other_pairs=[];worst_pair=None;table_force=np.zeros(3);table_moment=np.zeros(3)
  for i,c in enumerate(d.contact):
   a=m.geom(c.geom1).name;b=m.geom(c.geom2).name
   force=np.zeros(6);mujoco.mj_contactForce(m,d,i,force)
   if 'ball_geom' in (a,b):
    world=c.frame.reshape(3,3).T@force[:3];world*=1 if b=='ball_geom' else -1
    if 'table' in (a,b):
     table+=world[2];table_force+=world
     torque=c.frame.reshape(3,3).T@force[3:]*(1 if b=='ball_geom' else -1)
     table_moment+=np.cross(c.pos+OFF,world)+torque
    elif a.startswith(('pad','palm')) or b.startswith(('pad','palm')):N+=force[0];up+=world[2]
   elif 'table' in (a,b):
    world=c.frame.reshape(3,3).T@force[:3]*(1 if a=='table' else -1)
    table_force+=world
    table_moment+=np.cross(c.pos+OFF,world)+c.frame.reshape(3,3).T@force[3:]*(1 if a=='table' else -1)
    contact_other=max(contact_other,force[0])
    if force[0]>.001:other_pairs.append([a,b,float(force[0]),float(c.dist)])
   if -c.dist>pen:pen=-c.dist;worst_pair=[a,b,float(c.dist)]
  filtered+=DT/(.025+DT)*(N-filtered);prevN=N
  filtered_up+=DT/(.020+DT)*(up-filtered_up);prev_ball_acc=(up+table-.2*9.80665)/.2
  if t>=5.0 and table>.1*.2*9.80665 and surface_t is None:
   surface_t=t;surface_hand_z=C[2];events.append({'event':'surface_contact','t':t})
  if surface_t is not None and release_t is None:
   if table>.90*.2*9.80665 and abs(up)<.10*.2*9.80665:
    if stable_since is None:stable_since=t
    stable=t-stable_since
   else:stable=0;stable_since=None
   if stable>=.1:
    release_t=t;release_origin=(d.xpos[m.body('hand').id]+OFF).copy();stage='release';events.append({'event':'support_gate','t':t,'table_N':table,'hand_up_N':up})
   else:pass  # Vertical hand motor unloads onto the surface under force control.
  if release_t is not None and withdraw_t is None and t-release_t>.60 and N<.05:
   withdraw_t=t;withdraw_origin=(d.xpos[m.body('hand').id]+OFF).copy();stage='withdraw'
   try:_withdraw_plan=Plan(t,8.0,lambda u:desired(u,'withdraw',withdraw_t,land_z,withdraw_origin),lambda u:np.array([0.,-.20,1.40])+body(u),L1,LE,start_locked=True,start_elbow=E)
   except ValueError:
    raise
   events.append({'event':'finger_clear_gate','t':t,'N':N})
  if withdraw_t is not None:stage='withdraw'
  # Actual dynamic hand transform; anatomical pose is audited separately.
  bid=m.body('hand').id;hc=d.xpos[bid]+OFF;hr=d.xmat[bid].reshape(3,3)
  row={'t':t,'physics_time_s':float(d.time),'ball_velocity':d.qvel[m.joint(0).dofadr[0]:m.joint(0).dofadr[0]+3].tolist(),'ball_acceleration':d.qacc[m.joint(0).dofadr[0]:m.joint(0).dofadr[0]+3].tolist(),'C':hc.tolist(),'R':hr.tolist(),'ball':(d.xpos[m.body('ball').id]+OFF).tolist(),'ball_quat':d.xquat[m.body('ball').id].tolist(),'N':N,'up':up,'table':table,'table_force':table_force.tolist(),'table_moment':table_moment.tolist(),'other_table_N':contact_other,'penetration':pen,'alpha':float(alpha),'stage':stage,'command_C':C.tolist(),'command_R':R.tolist(),'reference_E':E.tolist(),'geoms':{},'other_pairs':[],'worst_pair':None}
  for name in ['palm']+[f'pad{f}_{j}' for f in range(5) for j in range(3)]:
   gid=m.geom(name).id;row['geoms'][name]={'p':(d.geom_xpos[gid]+OFF).tolist(),'R':d.geom_xmat[gid].reshape(3,3).tolist(),'size':m.geom(name).size.tolist()}
  row['other_pairs']=other_pairs;row['worst_pair']=worst_pair;rows.append(row)
 return {'rows':rows,'events':events,'xml':xml,'scene_duration_s':float(d.time),'integration_steps':round(8/DT)}
