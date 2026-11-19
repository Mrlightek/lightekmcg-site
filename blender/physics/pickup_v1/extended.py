import numpy as np
from scipy.optimize import linprog

def segment_box(a,b,lo,hi):
    a=np.asarray(a);b=np.asarray(b);v=b-a;n=len(a)
    with np.errstate(divide='ignore',invalid='ignore'):
        cuts=np.concatenate([np.zeros((n,1)),np.ones((n,1)),(lo-a)/v,(hi-a)/v],axis=1)
    cuts=np.sort(np.clip(np.nan_to_num(cuts,nan=0,posinf=1,neginf=0),0,1),axis=1)
    left=cuts[:,:-1];right=cuts[:,1:];mid=(left+right)/2
    p=a[:,None,:]+mid[:,:,None]*v[:,None,:]
    bound=np.where(p<lo,lo,np.where(p>hi,hi,p));active=(p<lo)|(p>hi)
    den=np.sum(active*v[:,None,:]**2,axis=2)
    num=np.sum(active*v[:,None,:]*(a[:,None,:]-bound),axis=2)
    t=np.clip(-num/np.maximum(den,1e-30),left,right)
    p=a[:,None,:]+t[:,:,None]*v[:,None,:]
    delta=np.maximum(np.maximum(lo-p,p-hi),0)
    return np.sqrt(np.min(np.sum(delta*delta,axis=2),axis=1))

def segment_segment(a,b,c,d):
    u=b-a;v=d-c;w=a-c;A=np.sum(u*u,axis=1);B=np.sum(u*v,axis=1);C=np.sum(v*v,axis=1);D=np.sum(u*w,axis=1);E=np.sum(v*w,axis=1)
    den=A*C-B*B;s=(B*E-C*D)/np.maximum(den,1e-30);t=(A*E-B*D)/np.maximum(den,1e-30)
    dist=np.linalg.norm(w+s[:,None]*u-t[:,None]*v,axis=1);dist[(s<0)|(s>1)|(t<0)|(t>1)|(den<1e-20)]=np.inf
    def point_segment(p,x,y):
        v=y-x;t=np.clip(np.sum((p-x)*v,axis=1)/np.maximum(np.sum(v*v,axis=1),1e-30),0,1)
        return np.linalg.norm(p-x-t[:,None]*v,axis=1)
    return np.minimum.reduce([dist,point_segment(a,c,d),point_segment(b,c,d),point_segment(c,a,b),point_segment(d,a,b)])

def validate(data,poses,F,M,DT):
    rows=data['rows'];ts=np.array([r['t'] for r in rows]);checks={};metrics={}
    velocity=np.array([r['ball_velocity'] for r in rows]);ball=np.array([r['ball'] for r in rows])
    region=(ts>=4.5)&(ball[:,2]<=1.002)&(ball[:,2]>=1.0)&(velocity[:,2]<0)
    speed=float(np.max(-velocity[region,2])) if np.any(region) else None
    checks['final_2mm_approach_speed']=speed is not None and speed<=.01
    metrics['final_2mm_descent_speed_max_m_s']=speed
    events={e['event']:e for e in data['events']}
    gate=events.get('support_gate');checks['release_within_placement_beat']=gate is not None and 4.5<=gate['t']<=6.25
    if gate:
        window=[r for r in rows if gate['t']-.1-1e-10<=r['t']<=gate['t']]
        metrics['release_gate_dwell_s']=window[-1]['t']-window[0]['t']
        metrics['release_gate_table_fraction_min']=min(r['table']/(.2*9.80665) for r in window)
        metrics['release_gate_abs_hand_fraction_max']=max(abs(r['up'])/(.2*9.80665) for r in window)
        checks['independent_release_gate']=metrics['release_gate_dwell_s']>=.1-1e-10 and metrics['release_gate_table_fraction_min']>.9 and metrics['release_gate_abs_hand_fraction_max']<.1
    else:checks['independent_release_gate']=False
    metrics['scene_duration_s']=data['scene_duration_s'];metrics['integration_steps']=data['integration_steps']
    checks['exact_8s_timeline']=len(rows)==round(8/DT)+1 and abs(ts[0])<1e-10 and abs(ts[-1]-8)<1e-10 and abs(data['scene_duration_s']-8)<1e-9 and max(abs(r['physics_time_s']-r['t']) for r in rows)<1e-9
    # Every force sample must be realizable by nonnegative corner forces on both feet.
    points=np.array([[x,y+side*.14,0] for side in [-1,1] for x in [-.11,.15] for y in [-.05,.05]])
    Aeq=np.zeros((6,24));friction=[]
    for i,p in enumerate(points):
        Aeq[:3,i*3:i*3+3]=np.eye(3)
        Aeq[3:,i*3:i*3+3]=np.array([[0,-p[2],p[1]],[p[2],0,-p[0]],[-p[1],p[0],0]])
        for phi in np.arange(8)*np.pi/4:
            row=np.zeros(24);row[i*3:i*3+3]=[np.cos(phi),np.sin(phi),-.7*np.cos(np.pi/8)];friction.append(row)
    bad=[];max_residual=0.;normal_ranges=[[float('inf'),-float('inf')],[float('inf'),-float('inf')]]
    for i,(f,m) in enumerate(zip(F,M)):
        target=np.r_[f,m];result=linprog(np.zeros(24),A_ub=friction,b_ub=np.zeros(64),A_eq=Aeq,b_eq=target,bounds=[bound for _ in range(8) for bound in [(None,None),(None,None),(0,None)]],method='highs',options={'threads':1})
        if not result.success:bad.append(float(ts[i]));continue
        max_residual=max(max_residual,float(np.max(np.abs(Aeq@result.x-target))))
        for foot in range(2):
            normal=sum(result.x[(foot*4+j)*3+2] for j in range(4));normal_ranges[foot][0]=min(normal_ranges[foot][0],normal);normal_ranges[foot][1]=max(normal_ranges[foot][1],normal)
    checks['per_foot_contact_wrench']=not bad and max_residual<1e-6
    metrics['per_foot_wrench_infeasible_samples']=len(bad);metrics['per_foot_wrench_first_failure_s']=bad[0] if bad else None;metrics['per_foot_wrench_max_residual']=max_residual;metrics['foot_normal_ranges_N']=normal_ranges
    # Independently check capsule / pedestal geometry, not just solver contact forces.
    parts={p['name']:{key:np.array([q['parts'][j][key] for q in poses]) for key in ['a','b','p','R']}|{'r':p['r']} for j,p in enumerate(poses[0]['parts'])}
    lo=np.array([.28,-.42,.855]);hi=np.array([.64,-.02,.955]);min_gap=float('inf');min_pair=None;min_time=None
    for name,p in parts.items():
        if name=='ball' or name.startswith('foot'):continue
        if name=='palm':continue # OBB test still required; absence of contacts does not certify it.
        cloth=.003 if name in ['torso','pelvis','upperR','upperL','foreR','foreL'] or name.startswith(('thigh','shank')) else 0
        gaps=segment_box(p['a'],p['b'],lo,hi)-p['r']-cloth
        j=int(np.argmin(gaps))
        if gaps[j]<min_gap:min_gap=float(gaps[j]);min_pair=[name,'pedestal'];min_time=float(ts[j])
    metrics['capsule_pedestal_min_gap_m']=min_gap;metrics['capsule_pedestal_min_pair']=min_pair;metrics['capsule_pedestal_min_time_s']=min_time
    checks['capsule_pedestal_clearance']=min_gap>=0
    # This is deliberately partial until OBB, full body/clothing pairs, and swept bounds are verified.
    from clearance_checks import run
    clearance=run(poses,rows,segment_box,segment_segment);metrics.update(clearance);checks['full_body_clothing_hand_swept_clearance']=clearance['full_clearance_passed']
    checks['footprint_clearance_gate']='footprint_clear_gate' in events
    hold=np.array([r['C'] for r in rows if 3.25<=r['t']<=4.5]);excursion=float(np.max(np.linalg.norm(hold-hold[0],axis=1)));metrics['hold_hand_excursion_m']=excursion;checks['living_hold_displacement']=.001<=excursion<=.002
    metrics['max_intended_skin_contact_depth_m']=max(r['penetration'] for r in rows);checks['intended_contact_compliance_depth']=metrics['max_intended_skin_contact_depth_m']<=.002
    return checks,metrics
