"""Replay saved, bounded character direction against a native Blender source."""
import bpy
import math
import os
import subprocess
import visemes
import motion
from mathutils import Euler

SOUNDS = []


def frame_at(seconds, fps):
    return max(1, 1 + round(seconds * fps))


def apply_sequence(root, objects, definition):
    takes=definition.get('performance_takes')
    if not takes:
        apply(root,objects,definition)
    else:
        if not isinstance(takes,list) or len(takes)>32:
            raise RuntimeError('Use at most 32 character dialogue takes')
        base=str(definition.get('performance_instance',root.name))
        for index,take in enumerate(takes):
            apply(root,objects,dict(definition,performance=take,performance_instance=base+'_take_'+str(index)))
    apply_listener_reactions(objects, definition)


def apply_listener_reactions(objects, definition):
    # Reactions are silent overlays: they never create sound strips or mouth
    # keys, and the manager only places them outside this character's speech.
    cues=definition.get('listener_reactions',[])
    if not isinstance(cues,list) or len(cues)>4:
        raise RuntimeError('Use at most four listener reactions')
    profile=definition['character_profile']
    fps=bpy.context.scene.render.fps/bpy.context.scene.render.fps_base
    takes=definition.get('performance_takes') or [definition.get('performance')]
    for cue in cues:
        start=float(cue['start']);duration=float(cue['duration']);end=start+duration
        if cue.get('kind')!='listen' or not all(math.isfinite(v) for v in (start,duration)) or start<0 or duration<0.1 or end>8:
            raise RuntimeError('Invalid listener reaction timing')
        if any(take and start<take['start']+take['duration']-0.001 and end>take['start']+0.001 for take in takes):
            raise RuntimeError('Listener reactions cannot overlap this character speech')
        binding=profile['bindings'].get('brow_raise')
        if binding:
            mesh=objects[binding['object']]
            key=mesh.data.shape_keys.key_blocks[binding['key']]
            for t,value in ((start,0),(start+min(.12,duration/3),.32),(end-min(.12,duration/3),.32),(end,0)):
                key.value=value
                key.keyframe_insert(data_path='value',frame=frame_at(t,fps),group='Lightek listening')
        binding=profile.get('bones',{}).get('head')
        if binding:
            rig=objects[binding['object']];bone=rig.pose.bones[binding['bone']]
            bone.rotation_mode='XYZ'
            for i in range(17):
                ratio=i/16
                bone.rotation_euler=(math.sin(ratio*math.tau)*math.sin(ratio*math.pi)*.10,0,0)
                bone.keyframe_insert(data_path='rotation_euler',frame=frame_at(start+ratio*duration,fps),group='Lightek listening')


def apply(root, objects, definition):
    profile = definition['character_profile']
    take = definition.get('performance')
    if not take:
        return
    scene = bpy.context.scene
    fps = scene.render.fps / scene.render.fps_base
    start = float(take['start'])
    duration = float(take['duration'])
    end = start + duration
    bindings = profile['bindings']
    copied = set()

    def shape(control):
        binding = bindings[control]
        obj = objects.get(binding['object'])
        if obj is None or obj.type != 'MESH' or not obj.data.shape_keys:
            raise RuntimeError('The character facial mesh is unavailable: ' + binding['object'])
        if obj.name not in copied:
            obj.data = obj.data.copy()
            keys = obj.data.shape_keys
            if keys.animation_data and keys.animation_data.action:
                keys.animation_data.action = keys.animation_data.action.copy()
            copied.add(obj.name)
        key = obj.data.shape_keys.key_blocks.get(binding['key'])
        if key is None:
            raise RuntimeError('The character shape key is unavailable: ' + binding['key'])
        return key

    def animate(key, points):
        for seconds, value in sorted(points.items()):
            key.value = float(value)
            key.keyframe_insert(data_path='value', frame=frame_at(seconds, fps), group='Lightek performance')
        action = key.id_data.animation_data.action
        for curve in action.fcurves:
            if curve.data_path == key.path_from_id('value'):
                for point in curve.keyframe_points:
                    point.interpolation = 'LINEAR'

    mouth = visemes.curves(take['lip_sync']['cues'], duration=duration, start=start, fps=fps, bindings=bindings) if take.get('lip_sync_mode') == 'phoneme' else {}
    for control in bindings:
        if control in mouth:
            points = mouth[control].copy()
        else:
            points = {max(0, start - 1 / fps): 0, start: 0, end: 0}
        if control == 'jaw_open' and not mouth:
            for sample in take['mouth_frames']:
                if sample['time'] < duration:
                    points[start + sample['time']] = sample['value']
        if control == 'blink':
            t = start + 1.2
            while t + 0.18 < end:
                points.update({t: 0, t + 0.07: 1, t + 0.18: 0})
                t += 3.4
        for cue in take['expressions']:
            if cue['control'] == control:
                first = start + cue['start']; last = start + cue['end']
                edge = min(0.12, (last - first) / 3)
                points = {time: value for time, value in points.items() if time < first or time > last}
                points.update({first: 0, first + edge: cue['value'], last - edge: cue['value'], last: 0})
        animate(shape(control), points)

    motion_ids={clip['action_id'] for clip in definition.get('motion_clips',[])}
    motion_rigs={item['rig'] for item in profile.get('motions',[]) if item['id'] in motion_ids}
    for cue in take['gestures']:
        binding_key = {'nod': 'head', 'shake': 'head', 'wave_left': 'left_arm', 'wave_right': 'right_arm'}[cue['kind']]
        binding = profile['bones'][binding_key]
        rig = objects.get(binding['object'])
        if rig is None or rig.type != 'ARMATURE' or binding['bone'] not in rig.pose.bones:
            raise RuntimeError('The character gesture bone is unavailable')
        if rig.animation_data and rig.animation_data.action:
            rig.animation_data.action = rig.animation_data.action.copy()
        bone = rig.pose.bones[binding['bone']]
        base = Euler((0,0,0),'XYZ') if binding['object'] in motion_rigs else bone.matrix_basis.to_euler('XYZ')
        bone.rotation_mode = 'XYZ'
        for i in range(17):
            ratio = i / 16
            t = start + cue['start'] + ratio * (cue['end'] - cue['start'])
            angles = base.copy()
            axis = 0 if cue['kind'] == 'nod' else 2
            angles[axis] += math.sin(ratio * math.tau * 2) * math.sin(ratio * math.pi) * cue['strength'] * 0.6
            bone.rotation_euler = angles
            bone.keyframe_insert(data_path='rotation_euler', frame=frame_at(t, fps), group='Lightek performance')

    if definition.get('motion_clips') and take['gestures']:
        rigs={objects[profile['bones'][{'nod':'head','shake':'head','wave_left':'left_arm','wave_right':'right_arm'}[cue['kind']]]['object']] for cue in take['gestures']}
        for rig in rigs:
            if rig not in {objects[name] for name in motion_rigs}: continue
            action=rig.animation_data.action
            if action is None: continue
            slot=getattr(rig.animation_data,'action_slot',None)
            first,last=action.frame_range
            rig.animation_data.action=None
            motion.add_strip(rig,action,slot,name='Lightek gesture overlay',first=first,last=last,scene_start=first,mode='ADD')

    path = take.get('audio_path')
    if not path or not os.path.isfile(path):
        raise RuntimeError('The performance recording was not staged')
    editor = scene.sequence_editor_create()
    strips = editor.strips if hasattr(editor, 'strips') else editor.sequences
    # Reserved high channels keep character dialogue away from native picture tracks.
    channel = max(32, max((item.channel for item in strips), default=0) + 1)
    if channel > 128:
        raise RuntimeError('No free audio channel is available for this character')
    name = 'LightekVoice_' + str(definition.get('performance_instance', root.name))
    for old in list(strips):
        if old.name == name:
            strips.remove(old)
    strip = strips.new_sound(name, path, channel=channel, frame_start=1 + round((start - float(take['source_in'])) * fps))
    strip.frame_final_start = frame_at(start, fps)
    strip.frame_final_end = frame_at(end, fps)
    strip.volume = take['gain']
    strip.sound.pack()
    SOUNDS.append(take)


def mux_movie(path, force=False):
    if not SOUNDS and not force:
        return
    scene = bpy.context.scene
    fps = scene.render.fps / scene.render.fps_base
    duration = (scene.frame_end - scene.frame_start + 1) / fps
    # Mix the native scene, including its existing score, volume automation and
    # our packed voice strips. A character must not erase a project's soundtrack.
    mixed = os.path.splitext(path)[0] + '-mix.wav'
    # Ubuntu 24.04's Blender 4.0 reads these from render settings; newer
    # Blender versions expose them as mixdown operator arguments.
    options=dict(filepath=mixed, check_existing=False, container='WAV', codec='PCM', format='S24')
    properties=bpy.ops.sound.mixdown.get_rna_type().properties
    if 'mixrate' in properties:
        options['mixrate']=48000
    else:
        scene.render.ffmpeg.audio_mixrate=48000
    if 'channels' in properties:
        options['channels']='STEREO'
    else:
        scene.render.ffmpeg.audio_channels='STEREO'
    bpy.ops.sound.mixdown(**options)
    output = os.path.splitext(path)[0] + '-audio.mp4'
    args = ['ffmpeg', '-v', 'error', '-y', '-filter_complex_threads', '1', '-i', path,
            '-protocol_whitelist', 'file,pipe', '-i', mixed, '-map', '0:v:0', '-map', '1:a:0',
            '-af', 'alimiter=limit=0.95', '-c:v', 'copy', '-c:a', 'aac', '-t', str(duration), '-movflags', '+faststart', output]
    result = subprocess.run(args, capture_output=True, timeout=120)
    if result.returncode:
        raise RuntimeError('Performance audio mix failed: ' + result.stderr.decode(errors='replace')[-1000:])
    os.replace(output, path)
    os.remove(mixed)
