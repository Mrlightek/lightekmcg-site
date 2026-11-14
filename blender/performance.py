"""Replay saved, bounded character direction against a native Blender source."""
import bpy
import math
import os
import subprocess
import visemes

SOUNDS = []


def frame_at(seconds, fps):
    return max(1, 1 + round(seconds * fps))


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

    for cue in take['gestures']:
        binding_key = {'nod': 'head', 'shake': 'head', 'wave_left': 'left_arm', 'wave_right': 'right_arm'}[cue['kind']]
        binding = profile['bones'][binding_key]
        rig = objects.get(binding['object'])
        if rig is None or rig.type != 'ARMATURE' or binding['bone'] not in rig.pose.bones:
            raise RuntimeError('The character gesture bone is unavailable')
        if rig.animation_data and rig.animation_data.action:
            rig.animation_data.action = rig.animation_data.action.copy()
        bone = rig.pose.bones[binding['bone']]
        base = bone.matrix_basis.to_euler('XYZ')
        bone.rotation_mode = 'XYZ'
        for i in range(17):
            ratio = i / 16
            t = start + cue['start'] + ratio * (cue['end'] - cue['start'])
            angles = base.copy()
            axis = 0 if cue['kind'] == 'nod' else 2
            angles[axis] += math.sin(ratio * math.tau * 2) * math.sin(ratio * math.pi) * cue['strength'] * 0.6
            bone.rotation_euler = angles
            bone.keyframe_insert(data_path='rotation_euler', frame=frame_at(t, fps), group='Lightek performance')

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


def mux_movie(path):
    if not SOUNDS:
        return
    scene = bpy.context.scene
    fps = scene.render.fps / scene.render.fps_base
    duration = (scene.frame_end - scene.frame_start + 1) / fps
    # Mix the native scene, including its existing score, volume automation and
    # our packed voice strips. A character must not erase a project's soundtrack.
    mixed = os.path.splitext(path)[0] + '-mix.wav'
    bpy.ops.sound.mixdown(filepath=mixed, check_existing=False, container='WAV', codec='PCM', format='S24', mixrate=48000, channels='STEREO')
    output = os.path.splitext(path)[0] + '-audio.mp4'
    args = ['ffmpeg', '-v', 'error', '-y', '-filter_complex_threads', '1', '-i', path,
            '-protocol_whitelist', 'file,pipe', '-i', mixed, '-map', '0:v:0', '-map', '1:a:0',
            '-af', 'alimiter=limit=0.95', '-c:v', 'copy', '-c:a', 'aac', '-t', str(duration), '-movflags', '+faststart', output]
    result = subprocess.run(args, capture_output=True, timeout=120)
    if result.returncode:
        raise RuntimeError('Performance audio mix failed: ' + result.stderr.decode(errors='replace')[-1000:])
    os.replace(output, path)
    os.remove(mixed)
