"""CPU articulated contact simulation. The load has a free joint, never a weld.

The palm's translation is motor driven. This is a hand/contact model, not a
whole-body musculoskeletal simulation. SI units; fixed step; no renderer/GPU.
"""
import argparse
import json
import math
from pathlib import Path
import mujoco
import numpy as np

PROFILE = Path(__file__).with_name('human_v1.json')

def smooth(x):
    x = np.clip(x, 0, 1)
    return float(x*x*(3-2*x))

def pulse(t,start,end):
    if not start < t < end:return 0.
    return .5*(1-math.cos(2*math.pi*(t-start)/(end-start)))

def trajectory(t):
    # Seconds are authored on a 12 fps beat grid. No load parenting/teleporting.
    if t < .25:return [0,-.30,.20],0
    if t < 1.25:
        u=smooth((t-.25)/1.0)
        return [0,-.30*(1-u),.20*(1-u)],0
    if t < 22/12:return [0,0,0],smooth((t-1.25)/(7/12))
    if t < 2:return [0,0,.002*smooth((t-22/12)/(2/12))],1
    if t < 26/12:return [0,0,.002+.004*smooth((t-2)/(2/12))-.001*pulse(t,2,26/12)],1
    if t < 2.25:return [0,0,.006+.002*smooth((t-26/12)/(1/12))],1
    if t < 3:return [0,0,.008+.142*smooth((t-2.25)/.75)],1
    if t < 4.5:
        phase=2*math.pi*(t-3)/1.5
        return [.001*(1-math.cos(phase)),0,.15+.002*math.sin(phase)],1
    if t < 5.5:return [0,0,.15*(1-smooth((t-4.5)/1.0))],1
    if t < 74/12:return [0,0,0],1-smooth((t-5.5)/(8/12))
    if t < 79/12:
        u=smooth((t-74/12)/(5/12));return [0,-.07*u,.012*u],0
    if t < 7.5:
        u=smooth((t-79/12)/(11/12));return [-.04*u,-.07-.23*u,.012+.118*u],0
    return [-.04,-.30,.13],0

def controls(t,goals):
    values=goals.copy()
    for f in range(5):
        for j in range(3):
            start=1.25+(0 if f==4 else .04*f)+.025*j
            close=smooth((t-start)/.40)
            release_start=5.75 if f==4 else 5.5+.04*f
            release=smooth((t-release_start)/(5/12))
            adjust=(.018*pulse(t,3.25,3.75) if f in (0,1) and j>0 else .010*pulse(t,43/12,4) if f==4 and j>0 else 0)
            values[f*3+j]=(goals[f*3+j]+adjust)*close*(1-release)
    return values


def model(profile):
    bodies, actuators, goals = [], [], []
    for finger, z in enumerate([-.027, -.009, .009, .027, 0]):
        thumb = finger == 4
        radius = .007 if thumb else .0065
        length = .035
        rc = math.sqrt(profile['prop_radius_m']**2-z*z)+radius-.0008
        delta = 2*math.atan(length/(2*rc))
        angle = math.radians(-150 if thumb else -30)
        rv = math.sqrt(rc*rc+(length/2)**2)
        root = [rv*math.cos(angle), rv*math.sin(angle), z]
        quat = '0 0 0 1' if thumb else '1 0 0 0'
        xml = f'<body name="finger{finger}_0" pos="{root[0]} {root[1]} {z}" quat="{quat}">'
        for joint in range(3):
            if joint: xml += f'<body name="finger{finger}_{joint}" pos=".035 0 0">'
            name = f'joint{finger}_{joint}'
            goal = math.radians(60)+delta/2 if joint == 0 else delta
            goals.append(goal+.05)
            # Fifteen moving links share the hand's mass budget; the palm gets 1/3.
            mass = profile['body_mass_kg']*profile['segment_mass_fractions']['hand']*(2/3)/15
            lo, hi = profile['finger_flexion_deg'][joint]
            xml += f'<joint name="{name}" axis="0 0 {-1 if thumb else 1}" range="{lo} {hi}"/><geom name="pad{finger}_{joint}" type="capsule" fromto="0 0 0 .035 0 0" size="{radius}" mass="{mass}"/>'
            torque = profile['finger_torque_limit_nm']
            actuators.append(f'<position joint="{name}" kp="{profile["finger_motor_stiffness_nm_rad"]}" kv="{profile["finger_motor_damping_nm_s_rad"]}" forcerange="-{torque} {torque}" ctrlrange="0 {math.radians(hi)}"/>')
        bodies.append(xml+'</body>'*3)
    for axis, xyz in zip('xyz', ['1 0 0', '0 1 0', '0 0 1']):
        actuators.append(f'<position joint="hand_{axis}" kp="3000" kv="50" forcerange="-150 150" ctrlrange="-.5 .5"/>')
    joints = ''.join(f'<joint name="hand_{a}" type="slide" axis="{v}" limited="false"/>' for a,v in zip('xyz',['1 0 0','0 1 0','0 0 1']))
    friction = ' '.join(map(str, profile['friction']))
    palm_mass = profile['body_mass_kg']*profile['segment_mass_fractions']['hand']/3
    xml = f'''<mujoco><compiler angle="degree" autolimits="true"/>
    <option timestep="{profile['timestep_s']}" integrator="implicitfast" cone="elliptic" iterations="100" noslip_iterations="5" gravity="0 0 -{profile['gravity_m_s2']}"/>
    <default><joint damping=".03" armature=".00002"/><geom friction="{friction}" condim="4" solref=".01 1" solimp=".95 .99 .001"/></default>
    <worldbody><geom name="floor" type="plane" size="1 1 .1"/><geom name="table" type="box" pos="0 0 .05" size=".18 .20 .05"/>
    <body name="ball" pos="0 0 .145"><freejoint/><geom name="ball_geom" type="sphere" size="{profile['prop_radius_m']}" mass="{profile['prop_mass_kg']}"/></body>
    <body name="hand" pos="0 0 .145">{joints}<geom name="palm" type="box" pos="-.02 -.065 0" size=".045 .008 .045" mass="{palm_mass}"/>{''.join(bodies)}</body></worldbody>
    <actuator>{''.join(actuators)}</actuator></mujoco>'''
    contact=json.loads(Path(__file__).with_name('pedestal_contact_v3.json').read_text())
    friction=' '.join(map(str,contact['friction']))
    xml=xml.replace('<geom name="table" type=',f'<geom name="table" condim="{contact["condim"]}" priority="{contact["priority"]}" friction="{friction}" type=')
    return xml, np.array(goals)

def simulate(profile=None):
    p = json.loads(PROFILE.read_text()) if profile is None else profile
    xml, goals = model(p)
    m = mujoco.MjModel.from_xml_string(xml)
    d = mujoco.MjData(m)
    # Initialize motor translation to the approach pose; no teleporting after step 0.
    for axis, value in zip('xyz', trajectory(0)[0]):
        d.qpos[m.joint('hand_'+axis).qposadr[0]] = value
    d.ctrl[-3:] = trajectory(0)[0]
    mujoco.mj_forward(m,d)
    names = ['palm']+[f'pad{f}_{j}' for f in range(5) for j in range(3)]
    frames, max_penetration, max_torque = [], 0., 0.
    max_joint = 0.; min_joint = 0.; max_contacts = 0
    steps = round(p['duration_s']/p['timestep_s'])
    next_sample = 0
    for step in range(steps):
        t = step*p['timestep_s']
        position, close = trajectory(t)
        d.ctrl[:-3] = controls(t,goals)
        d.ctrl[-3:] = position
        mujoco.mj_step(m,d)
        max_penetration = max(max_penetration, max((-c.dist for c in d.contact), default=0.))
        max_torque = max(max_torque, float(np.max(np.abs(d.actuator_force[:-3]))))
        angles = [d.qpos[m.joint(f'joint{f}_{j}').qposadr[0]] for f in range(5) for j in range(3)]
        max_joint = max(max_joint,max(angles)); min_joint = min(min_joint,min(angles))
        contact_count = sum(m.geom(c.geom1).name=='ball_geom' or m.geom(c.geom2).name=='ball_geom' for c in d.contact if m.geom(c.geom1).name!='table' and m.geom(c.geom2).name!='table')
        max_contacts = max(max_contacts,contact_count)
        if t >= next_sample/p['fps']-1e-9:
            mujoco.mj_forward(m,d)
            geoms = {name:{'position':d.geom_xpos[m.geom(name).id].tolist(),'rotation':d.geom_xmat[m.geom(name).id].reshape(3,3).tolist(),'size':m.geom(name).size.tolist()} for name in names}
            frames.append({'frame':next_sample+1,'time_s':t,'ball':d.xpos[m.body('ball').id].tolist(),'ball_quaternion':d.xquat[m.body('ball').id].tolist(),'hand':d.xpos[m.body('hand').id].tolist(),'geoms':geoms,'finger_angles_rad':angles,'load_contacts':int(contact_count),'motor_targets_rad':d.ctrl[:-3].tolist()})
            next_sample += 1
    held = [f for f in frames if 3.1<=f['time_s']<=3.9]
    released = [f for f in frames if f['time_s']>=7]
    report = {'solver':'mujoco','solver_version':mujoco.__version__,'profile':p,'steps':steps,'max_penetration_m':max_penetration,'max_finger_torque_nm':max_torque,'max_flexion_rad':max_joint,'min_flexion_rad':min_joint,'max_load_contacts':max_contacts,'lift_m':min(f['ball'][2] for f in held)-.145,'settled_height_m':float(np.mean([f['ball'][2] for f in released])),'prop_constraints':0,'whole_body_dynamics':False}
    held_frames=[f for f in frames if 3<=f['time_s']<=4.5]
    report['hold_load_travel_m']=max(np.linalg.norm(np.array(f['ball'])-held_frames[0]['ball']) for f in held_frames)
    report['hold_finger_adjustment_rad']=max(max(abs(a-b) for a,b in zip(f['finger_angles_rad'],held_frames[0]['finger_angles_rad'])) for f in held_frames)
    report['min_hold_contacts']=min(f['load_contacts'] for f in held_frames)
    report['pedestal_contact']=json.loads(Path(__file__).with_name('pedestal_contact_v3.json').read_text())
    report['acting_beats_s']={'commit':[0,22/12],'engage_lift':[22/12,3],'hold_assess':[3,4.5],'place_disengage':[4.5,8]}
    return {'frames':frames,'report':report,'model_xml':xml}

if __name__ == '__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--output',required=True)
    args=parser.parse_args()
    Path(args.output).write_text(json.dumps(simulate(),allow_nan=False))
