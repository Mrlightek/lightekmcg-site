import numpy as np

def run(poses,rows,segment_box,segment_segment):
    ts=np.array([r['t'] for r in rows]);names=[p['name'] for p in poses[0]['parts']]
    parts={name:{key:np.array([q['parts'][j][key] for q in poses]) for key in ['a','b','p','R']}|{'r':poses[0]['parts'][j]['r']} for j,name in enumerate(names)}
    body=[n for n in names if n not in ['palm','ball'] and not n.startswith(('pad','foot'))]
    pads=[n for n in names if n.startswith('pad')]
    def radius(name):return parts[name]['r']+(.003 if name not in pads+['ball','head','handL'] else 0)
    def movement(p):return np.maximum(np.linalg.norm(np.diff(p['a'],axis=0),axis=1),np.linalg.norm(np.diff(p['b'],axis=0),axis=1))
    worst={'gap_m':float('inf')};worst_swept={'gap_m':float('inf')}
    def record(gaps,pair,motion):
        i=int(np.argmin(gaps))
        if gaps[i]<worst['gap_m']:worst.update(gap_m=float(gaps[i]),pair=pair,time_s=float(ts[i]))
        swept=np.minimum(gaps[:-1],gaps[1:])-motion;i=int(np.argmin(swept))
        if swept[i]<worst_swept['gap_m']:worst_swept.update(gap_m=float(swept[i]),pair=pair,time_s=float(ts[i]))
    lo=np.array([.28,-.42,.855]);hi=np.array([.64,-.02,.955])
    for name in body+pads:
        p=parts[name];record(segment_box(p['a'],p['b'],lo,hi)-radius(name),[name,'pedestal'],movement(p))
        record(np.minimum(p['a'][:,2],p['b'][:,2])-radius(name),[name,'floor'],movement(p))
    # Overlapping joint envelopes form one continuous skin surface at these anatomical attachments.
    adjacent=[('torso','pelvis'),('torso','head'),('torso','upperR'),('torso','upperL'),('torso','thigh-1'),('torso','thigh1'),('pelvis','thigh-1'),('pelvis','thigh1'),('upperR','foreR'),('upperL','foreL'),('foreL','handL'),('wristL','handL'),('foreL','wristL'),('foreR','wristR'),('thigh-1','shank-1'),('thigh1','shank1')]
    excluded={frozenset(x) for x in adjacent}
    for i,a in enumerate(body):
        for b in body[i+1:]+pads+['ball']:
            if frozenset((a,b)) in excluded:continue
            p=parts[a];q=parts[b];record(segment_segment(p['a'],p['b'],q['a'],q['b'])-radius(a)-radius(b),[a,b],movement(p)+movement(q))
    palm=parts['palm'];size=np.array(rows[0]['geoms']['palm']['size']);R=palm['R'];P=palm['p'];half=(hi-lo)/2;center=(hi+lo)/2;delta=P-center
    axes=[np.broadcast_to(x,(len(rows),3)) for x in np.eye(3)]+[R[:,:,j] for j in range(3)]
    axes += [np.cross(np.broadcast_to(x,(len(rows),3)),R[:,:,j]) for x in np.eye(3) for j in range(3)]
    separations=[]
    for ax in axes:
        length=np.linalg.norm(ax,axis=1);axis=ax/np.maximum(length[:,None],1e-30)
        gap=np.abs(np.sum(delta*axis,axis=1))-np.sum(np.abs(axis)*half,axis=1)-np.sum(np.abs(np.einsum('ni,nij->nj',axis,R))*size,axis=1);gap[length<1e-9]=-np.inf;separations.append(gap)
    palm_gap=np.max(separations,axis=0)
    trace=np.einsum('nij,nij->n',R[:-1],R[1:]);angular=np.arccos(np.clip((trace-1)/2,-1,1));palm_motion=np.linalg.norm(np.diff(P,axis=0),axis=1)+np.linalg.norm(size)*angular
    record(palm_gap,['palm','pedestal'],palm_motion)
    for name in body+['ball']:
        if name=='wristR' or name=='ball':continue # wrist skin union; ball/palm is an intended grip contact.
        p=parts[name];a=np.einsum('nji,nj->ni',R,p['a']-P);b=np.einsum('nji,nj->ni',R,p['b']-P)
        record(segment_box(a,b,-size,size)-radius(name),['palm',name],palm_motion+movement(p))
    return {'full_clearance_discrete':worst,'full_clearance_swept_bound':worst_swept,'full_clearance_passed':worst_swept['gap_m']>=0}
