"""Run with Blender --background --python ... -- SOURCE_ROOT WAV CUES OUTPUT.
Verify saved editable animation and render two different mouth shapes from real speech.
"""
import bpy
import json
from pathlib import Path
import sys
root,wav,cues_path,output=sys.argv[sys.argv.index('--')+1:]
sys.path.insert(0,str(Path(root)/'blender'))
import performance
scene=bpy.context.scene
scene.render.fps=24
cues=json.loads(Path(cues_path).read_text())['mouthCues'];duration=cues[-1]['end']
bindings={f'viseme_{s}':{'object':'FaceMouth','key':f'viseme_{s}'} for s in 'abcdefghx'}
bindings.update({name:{'object':'FaceMouth','key':name} for name in ('jaw_open','mouth_wide','mouth_round','smile')})
objects={o.name:o for o in scene.objects};mouth=objects['FaceMouth'];original=mouth.data
performance.apply(objects['PerformerRig'],objects,{'character_profile':{'bindings':bindings,'bones':{}},'performance':{
    'start':0,'duration':duration,'source_in':0,'gain':1,'audio_path':wav,'mouth_frames':[],
    'lip_sync_mode':'phoneme','lip_sync':{'cues':cues},'expressions':[],'gestures':[]}})
assert mouth.data!=original
keys=mouth.data.shape_keys
assert keys.animation_data.action
selected=[]
for label in ('A','C','F'):
    cue=next((c for c in cues if c['value']==label and c['end']-c['start']>.07),None)
    if not cue:continue
    frame=1+round((cue['start']+cue['end'])/2*24);scene.frame_set(frame)
    assert keys.key_blocks['viseme_'+label.lower()].value>.5,label
    assert keys.key_blocks['jaw_open'].value==0
    selected.append((label,frame))
assert len(selected)>=2
scene.frame_end=1+round(duration*24);scene.frame_set(scene.frame_end)
assert all(keys.key_blocks['viseme_'+s].value==0 for s in 'abcdefghx')
strips=scene.sequence_editor.strips if hasattr(scene.sequence_editor,'strips') else scene.sequence_editor.sequences
assert all(s.sound.packed_file for s in strips if s.type=='SOUND')
bpy.ops.wm.save_as_mainfile(filepath=str(Path(output)/'speech-performance.blend'))
scene.render.resolution_x=160;scene.render.resolution_y=160;scene.cycles.samples=1;scene.cycles.use_denoising=False
for layer in scene.view_layers: layer.cycles.use_denoising=False
for label,frame in selected[:2]:
    scene.frame_set(frame);scene.render.filepath=str(Path(output)/f'mouth-{label}.png');bpy.ops.render.render(write_still=True)
print('LIGHTEK_PHONEME_BLENDER_PASS '+json.dumps({'cues':len(cues),'rendered_shapes':selected[:2],'packed_audio':True}))
