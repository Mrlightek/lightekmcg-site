"""Exact, source-keyed performance beats for the pedestal grasp."""
import math
from bench_v1 import smooth,key_object

BEATS={'commit':[0,22/12],'engage_lift':[22/12,3],'hold_assess':[3,4.5],'place_disengage':[4.5,8]}

def state(t):
    commitment=smooth(t/1.25)*(1-smooth((t-74/12)/(16/12)))
    recovery=smooth((t-74/12)/(19/12))
    knots=[(0,-.25),(13/12,1),(34/12,-.9),(45/12,.7),(67/12,-.7),(78/12,.5),(94/12,-.95),(8,-.88)]
    breath=knots[-1][1]
    for (a,av),(b,bv) in zip(knots,knots[1:]):
        if a<=t<=b:
            breath=av+(bv-av)*smooth((t-a)/(b-a));break
    return {'hip_forward_m':.006*commitment,'hip_lateral_m':.0015*math.sin(t*1.1),'body_drop_m':-.100+.025*recovery+.0015*breath,
            'breath':breath,'chest_scale':1+.006*(1+breath)/2,'gaze_weight':(.65+.35*smooth(t/(2/12)))*(1-.70*smooth((t-7)/.75)),
            'head_recovery':smooth((t-7)/.75)}

def chest(root,states):
    names={'Jacket body','Side Jacket body','Shirt'}
    objects=[o for o in root.children_recursive if o.get('lightek_source_object') in names]
    bases={o:o.scale.copy() for o in objects}
    for frame,acting in states:
        for obj in objects:
            obj.scale=bases[obj].copy();obj.scale.x*=acting['chest_scale'];obj.scale.z*=acting['chest_scale']
            obj.keyframe_insert(data_path='scale',frame=frame)
