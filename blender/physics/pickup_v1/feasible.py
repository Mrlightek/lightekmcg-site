import json,math,sys
from pathlib import Path
import numpy as np
from scipy.spatial.transform import Rotation
from solve import body,DT,MOUNT,ease
from ik import constrained_elbow,ElbowTracker
_trackers={-1:ElbowTracker(),1:ElbowTracker()}

def unit(v):return np.array(v)/np.linalg.norm(v)
def rotz(a):return np.array([[math.cos(a),-math.sin(a),0],[math.sin(a),math.cos(a),0],[0,0,1]])
def roty(a):return np.array([[math.cos(a),0,math.sin(a)],[0,1,0],[-math.sin(a),0,math.cos(a)]])
def frame(a,b):
 z=unit(np.array(b)-a);x=np.cross([0,1,0],z)
 if np.linalg.norm(x)<1e-5:x=np.cross([1,0,0],z)
 x=unit(x);return np.column_stack([x,np.cross(z,x),z])
def elbow(S,W,a,b,pole=np.array([0.,-.3,-1.]),hand_axis=None):
 return _trackers[-1 if pole[1]<0 else 1].solve(S,W,a,b,axis_target=hand_axis,side=-1 if pole[1]<0 else 1)

def model(row):
 t=row['t']
 if t==0:_trackers.update({-1:ElbowTracker(),1:ElbowTracker()})
 B=body(t);C=np.array(row['C']);R=np.array(row['R']);W=C+R@MOUNT;S=B+[0,-.20,1.40];E=None
 if 'reference_E' in row:
  v=W-S;dist=np.linalg.norm(v);axis=v/dist;along=(.30**2-.26**2+dist*dist)/(2*dist);h=math.sqrt(max(0,.30**2-along**2));base=S+axis*along
  bend=np.array(row['reference_E'])-base;bend-=axis*np.dot(bend,axis);E=base+unit(bend)*h
 else:E=elbow(S,W,.30,.26,hand_axis=R[:,0])
 D=unit(W-E);relative=R.T@D;flex=math.degrees(math.atan2(relative[1],relative[0]));dev=math.degrees(math.atan2(relative[2],relative[0]));upper=unit(E-S)
 ball=np.array(row['ball']);neck=B+[0,0,1.5];target=ball.copy()
 if t>7:target=ball+(np.array([.62,-.22,.955])-ball)*ease((t-7)/.75)
 yaw=math.atan2(-.22,.46)+math.radians(.35)*math.sin(.8*t);nod=(20+10*ease(t/(2/12)))*(1-ease((t-7)/.75))+20*ease((t-7)/.75)
 HR=rotz(yaw)@roty(math.radians(nod));eyes=[]
 for side in [-1,1]:
  origin=neck+HR@np.array([.110,side*.042,.130]);ray=unit(target-origin);v=HR.T@ray
  eyes.append({'o':origin.tolist(),'d':ray.tolist(),'pitch':math.degrees(math.atan2(-v[2],v[0])),'yaw':math.degrees(math.atan2(v[1],v[0]))})
 head=neck+HR@np.array([.02,0,.13]);parts=[]
 def part(name,m,a,b,r,Rgiven=None):
  a=np.array(a);b=np.array(b);l=np.linalg.norm(b-a);p=(a+b)/2;Q=frame(a,b) if Rgiven is None and l>1e-6 else np.eye(3) if Rgiven is None else Rgiven
  mc=m*l/(l+4*r/3) if l>0 else 0;ms=m-mc
  I=np.diag([mc*(l*l/12+r*r/4)+ms*(.4*r*r+l*l/4+3*l*r/8)]*2+[.5*mc*r*r+.4*ms*r*r])
  if name in ('head','ball'):I=np.eye(3)*(.4*m*r*r)
  if name.startswith('foot'):I=np.diag([m*(.10**2+.08**2)/12,m*(.26**2+.08**2)/12,m*(.26**2+.10**2)/12])
  parts.append({'name':name,'mass':m,'p':p,'R':Q,'I':I,'a':a,'b':b,'r':r})
 part('torso',26.025,B+[0,0,.98],B+[0,0,1.37],.15)
 part('pelvis',11.25,B+[0,0,.84],B+[0,0,.94],.14)
 part('head',6.075,head,head,.115,HR)
 part('upperR',2.1,S,E,.045);transition=W-D*.045;part('foreR',1.05,E,transition,.033);part('wristR',.15,transition,W,.022)
 for name,g in row['geoms'].items():
  p=np.array(g['p']);Q=np.array(g['R']);size=g['size'];m=.15 if name=='palm' else .02
  if name=='palm':
   I=np.diag([m*(size[1]**2+size[2]**2)/3,m*(size[0]**2+size[2]**2)/3,m*(size[0]**2+size[1]**2)/3]);a=p;b=p;r=max(size)
  else:
   a=p-Q[:,2]*size[1];b=p+Q[:,2]*size[1];r=size[0];l=2*size[1];mc=m*l/(l+4*r/3);ms=m-mc;I=np.diag([mc*(l*l/12+r*r/4)+ms*(.4*r*r+l*l/4+3*l*r/8)]*2+[.5*mc*r*r+.4*ms*r*r])
  parts.append({'name':name,'mass':m,'p':p,'R':Q,'I':I,'a':a,'b':b,'r':r})
 S2=B+[0,.20,1.40];W2=B+[.06,.23,.85];E2=constrained_elbow(S2,W2,.30,.26,side=1)
 part('upperL',2.1,S2,E2,.045);transition2=W2-unit(W2-E2)*.045;part('foreL',1.05,E2,transition2,.033);part('wristL',.15,transition2,W2,.022);part('handL',.45,W2+[0,0,-.05],W2+[0,0,-.09],.04)
 knees=[]
 for side in [-1,1]:
  hip=B+[0,side*.095,.90];ankle=np.array([.02,side*.14,.09]);v=ankle-hip;d=np.linalg.norm(v);axis=v/d;along=(.4**2-.42**2+d*d)/(2*d);bend=unit(np.array([1.,0,0])-axis*np.dot([1,0,0],axis));knee=hip+axis*along+bend*math.sqrt(.4**2-along**2)
  knees.append(math.degrees(math.acos(np.clip(np.dot(unit(knee-hip),unit(ankle-knee)),-1,1))))
  part('thigh'+str(side),7.5,hip,knee,.07);part('shank'+str(side),3.4875,knee,ankle,.05);part('foot'+str(side),1.0875,[.02,side*.14,.04],[.02,side*.14,.04],.10)
 quat=row['ball_quat'];part('ball',.2,ball,ball,.045,Rotation.from_quat([quat[1],quat[2],quat[3],quat[0]]).as_matrix())
 return {'parts':parts,'S':S,'E':E,'W':W,'wrist_flex':flex,'wrist_dev':dev,'elevation':math.degrees(math.acos(np.clip(-upper[2],-1,1))),'eyes':eyes,'knees':knees,'head':head,'headR':HR,'root':B}

def analyze(data):
 poses=[];failures=[]
 for row in data['rows']:
  try:poses.append(model(row))
  except ValueError as e:return {'accepted':False,'failure':'pose','detail':str(e),'time':row['t']}
 n=len(poses);names=[p['name'] for p in poses[0]['parts']];masses=np.array([p['mass'] for p in poses[0]['parts']]);mass=masses.sum()
 positions=np.array([[p['p'] for p in q['parts']] for q in poses]);vel=np.gradient(positions,DT,axis=0,edge_order=2);acc=np.gradient(vel,DT,axis=0,edge_order=2);com=np.sum(positions*masses[None,:,None],axis=1)/mass;comacc=np.sum(acc*masses[None,:,None],axis=1)/mass
 # Angular momentum includes spin inertia for every oriented rigid segment.
 H=np.sum(np.cross(positions,vel*masses[None,:,None]),axis=1)
 for j in range(len(names)):
  Rs=np.array([q['parts'][j]['R'] for q in poses]);dR=np.gradient(Rs,DT,axis=0);skew=np.einsum('nij,nkj->nik',dR,Rs);omega=np.stack([skew[:,2,1],skew[:,0,2],skew[:,1,0]],axis=1)
  if names[j] in ['torso','pelvis','upperR','foreR','upperL','foreL','wristR','wristL','handL','thigh-1','shank-1','thigh1','shank1']:
   z=Rs[:,:,2];omega=np.cross(z,np.gradient(z,DT,axis=0))
  Ilocal=poses[0]['parts'][j]['I'];Iworld=Rs@Ilocal@np.transpose(Rs,(0,2,1));H+=np.einsum('nij,nj->ni',Iworld,omega)
 Hd=np.gradient(H,DT,axis=0,edge_order=2)
 tableF=np.array([r.get('table_force',[0,0,r['table']]) for r in data['rows']]);tableM=np.array([r.get('table_moment',np.cross(r['ball'],[0,0,r['table']])) for r in data['rows']]);gravity=np.array([0,0,-9.80665]);F=mass*(comacc-gravity)-tableF;M=Hd-np.cross(com,mass*gravity)-tableM
 cop=np.column_stack([-M[:,1]/F[:,2],M[:,0]/F[:,2]])
 report={'accepted':True,'body_mass_kg':mass-.2,'balance_method':'centroidal_inverse_dynamics_contact_wrench_feasibility','wrist_flex_max_deg':max(abs(p['wrist_flex']) for p in poses),'wrist_dev_max_deg':max(abs(p['wrist_dev']) for p in poses),'shoulder_start_deg':poses[0]['elevation'],'shoulder_end_deg':poses[-1]['elevation'],'shoulder_hold_max_deg':max(p['elevation'] for p,r in zip(poses,data['rows']) if 3.25<=r['t']<4.5),'eye_pitch_max_deg':max(abs(e['pitch']) for p in poses for e in p['eyes']),'eye_yaw_max_deg':max(abs(e['yaw']) for p in poses for e in p['eyes']),'cop_x_range':list(map(float,[cop[:,0].min(),cop[:,0].max()])),'cop_y_range':list(map(float,[cop[:,1].min(),cop[:,1].max()])),'ground_Fz_range':list(map(float,[F[:,2].min(),F[:,2].max()])),'friction_ratio_max':float(np.max(np.linalg.norm(F[:,:2],axis=1)/F[:,2])),'max_lift_accel_up':max((r['up']+r['table']-.2*9.80665)/.2 for r in data['rows'] if 1.85<=r['t']<3.25),'max_pedestal_contact_N':max(r['other_table_N'] for r in data['rows'])}
 checks={'wrist_flex':report['wrist_flex_max_deg']<=15,'wrist_deviation':report['wrist_dev_max_deg']<=10,'start_arm':report['shoulder_start_deg']<25,'end_arm':report['shoulder_end_deg']<25,'hold_arm':report['shoulder_hold_max_deg']<60,'eye_bounds':report['eye_pitch_max_deg']<=40 and report['eye_yaw_max_deg']<=35,'positive_floor':bool(np.all(F[:,2]>0)),'support_patch':bool(np.all((cop[:,0]>=-.09)&(cop[:,0]<=.13)&(np.abs(cop[:,1])<=.12))),'floor_friction':report['friction_ratio_max']<=.7,'lift_acceleration':report['max_lift_accel_up']<=1,'pedestal_no_hand_collision':report['max_pedestal_contact_N']<.01,'support_gate':any(e['event']=='support_gate' for e in data['events']),'clear_gate':any(e['event']=='finger_clear_gate' for e in data['events'])}
 report['metric_times_s']={'wrist_flex':data['rows'][int(np.argmax([abs(p['wrist_flex']) for p in poses]))]['t'],'wrist_deviation':data['rows'][int(np.argmax([abs(p['wrist_dev']) for p in poses]))]['t'],'cop_x_min':data['rows'][int(np.argmin(cop[:,0]))]['t'],'cop_x_max':data['rows'][int(np.argmax(cop[:,0]))]['t'],'cop_y_min':data['rows'][int(np.argmin(cop[:,1]))]['t'],'cop_y_max':data['rows'][int(np.argmax(cop[:,1]))]['t'],'friction_max':data['rows'][int(np.argmax(np.linalg.norm(F[:,:2],axis=1)/F[:,2]))]['t'],'pedestal_contact_max':max(data['rows'],key=lambda r:r['other_table_N'])['t'],'lift_acceleration_max':max([r for r in data['rows'] if 1.85<=r['t']<3.25],key=lambda r:(r['up']+r['table']-.2*9.80665)/.2)['t']}
 hold_rows=[r for r in data['rows'] if 3.25<=r['t']<=4.5]
 report['hold_ball_z_range_m']=[min(r['ball'][2] for r in hold_rows),max(r['ball'][2] for r in hold_rows)]
 checks['lift_and_hold_arc']=all(1.14<=r['ball'][2]<=1.16 and r['N']>0 for r in hold_rows)
 from extended import validate
 extended_checks,extended_metrics=validate(data,poses,F,M,DT)
 checks.update(extended_checks);report.update(extended_metrics)
 report['checks']=checks;report['simulation_checks_passed']=bool(all(checks.values()));report['accepted']=False;report['required_checks_pending']=['calibrated_eye_mesh_ray_alignment','shared_world_state_across_render_cameras','render_mesh_to_physics_geometry_consistency'];return report
