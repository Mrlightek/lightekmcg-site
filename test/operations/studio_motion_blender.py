"""Native motion proof: inventory, retime, repeat, influence and independent rigs."""
import bpy
import json
from pathlib import Path
import sys
root,output=sys.argv[sys.argv.index('--')+1:]
sys.path.insert(0,str(Path(root)/'blender'))
import motion
import performance
scene=bpy.context.scene;scene.render.fps=24
rig=bpy.data.objects['PerformerRig'];specs=motion.inventory(rig)
assert len(specs)==3,specs
spec=next(item for item in specs if item['name']=='Head nod');spec.update(rig=rig.name,fps=24)
second=rig.copy();second.data=rig.data.copy();scene.collection.objects.link(second)
# A native duplicate gets its own NLA animation data, while source Actions stay shared.
source_action=motion.references(rig)[0][0]
source_frames=list(source_action.frame_range)
clip={'id':'head-motion-one','action_id':spec['id'],'source_in':1,'source_out':25,'start':1,'speed':.5,'repeat':2,'strength':.5,'blend_in':.25,'blend_out':.25,'layer':0,'mode':'REPLACE'}
definition={'character_profile':{'motions':[spec]},'motion_clips':[clip]}
motion.apply({rig.name:rig},definition)
strips=[s for t in rig.animation_data.nla_tracks if not t.mute for s in t.strips]
assert len(strips)==1
strip=strips[0]
assert abs(strip.frame_start-25)<1e-5 and abs(strip.frame_end-121)<1e-5,(strip.frame_start,strip.frame_end)
assert strip.repeat==2 and strip.scale==2
scene.frame_set(37)
value=rig.pose.bones['Head'].rotation_euler.x
assert abs(value-.125)<.015,value
assert abs(second.pose.bones['Head'].rotation_euler.x)<1e-5
scene.frame_set(25);assert abs(rig.pose.bones['Head'].rotation_euler.x)<1e-5
scene.frame_set(122);assert abs(rig.pose.bones['Head'].rotation_euler.x)<1e-5
assert source_frames==list(source_action.frame_range)
# Compose saved facial speech and additive gesture direction over body motion.
scene.frame_set(33);body_only=rig.pose.bones['Head'].rotation_euler.x
profile={'motions':[spec],'bindings':{'jaw_open':{'object':'FaceMouth','key':'jaw_open'},'viseme_d':{'object':'FaceMouth','key':'viseme_d'}},'bones':{'head':{'object':rig.name,'bone':'Head'}}}
definition.update(character_profile=profile,performance={'start':1,'duration':2,'source_in':0,'gain':1,'audio_path':str(Path(output)/'voice.wav'),
    'lip_sync_mode':'phoneme','lip_sync':{'cues':[{'start':0,'end':.5,'value':'A'},{'start':.5,'end':1.5,'value':'D'},{'start':1.5,'end':2,'value':'X'}]},'mouth_frames':[],
    'expressions':[],'gestures':[{'kind':'nod','start':0,'end':1,'strength':.6}]})
objects={o.name:o for o in scene.objects}
performance.apply(rig,objects,definition)
scene.frame_set(33)
assert abs(rig.pose.bones['Head'].rotation_euler.x-body_only)>.05,(rig.pose.bones['Head'].rotation_euler.x,body_only)
scene.frame_set(49);assert bpy.data.objects['FaceMouth'].data.shape_keys.key_blocks['viseme_d'].value>.9
assert len([t for t in rig.animation_data.nla_tracks if not t.mute])==2
strips_all=scene.sequence_editor.strips if hasattr(scene.sequence_editor,'strips') else scene.sequence_editor.sequences
assert any(s.type=='SOUND' and s.sound.packed_file for s in strips_all)
# Persist the mixed source and verify a genuine native Action/NLA strip survives.
bpy.ops.wm.save_as_mainfile(filepath=str(Path(output)/'motion-performance.blend'))
print('LIGHTEK_MOTION_BLENDER_PASS '+json.dumps({'source_actions':len(specs),'duration_frames':strip.frame_end-strip.frame_start,'weighted_angle':value,'independent':True}))
