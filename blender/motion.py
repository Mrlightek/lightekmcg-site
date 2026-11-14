"""Expose and replay source-bound Blender Actions through native NLA strips."""
import hashlib
import math
import bpy

SOURCE_NAME = 'lightek_motion_source'


def references(rig):
    animation = rig.animation_data
    if not animation:
        return []
    refs = ([animation] if animation.action else []) + [strip for track in animation.nla_tracks for strip in track.strips if strip.type == 'CLIP' and strip.action]
    return [(ref.action, getattr(ref, 'action_slot', None)) for ref in refs]


def inventory(rig):
    result = []
    for action, slot in references(rig):
        if action.library: continue
        source = action.get(SOURCE_NAME)
        if not isinstance(source,str) or not 1<=len(source)<=128: source=action.name
        action[SOURCE_NAME] = source
        identifier = slot.identifier if slot else ''
        identity = hashlib.sha256((rig.name+'\0'+source+'\0'+identifier).encode()).hexdigest()[:32]
        first, last = map(float, action.frame_range)
        if not all(math.isfinite(n) and abs(n)<=1000000 for n in (first,last)) or last<=first:
            continue
        if any(item['id']==identity for item in result):
            continue
        result.append({'id':identity, 'name':source, 'source':source, 'slot':identifier, 'frame_start':first, 'frame_end':last})
        if len(result)>=64: break
    return result


def add_strip(rig, action, slot, *, name, first, last, scene_start, scale=1, repeat=1, strength=1, blend_in=0, blend_out=0, mode='REPLACE'):
    animation=rig.animation_data_create()
    track=animation.nla_tracks.new(prev=animation.nla_tracks[-1]) if len(animation.nla_tracks) else animation.nla_tracks.new()
    track.name=name
    animation.use_nla=True
    strip=track.strips.new(name,int(math.floor(scene_start)),action)
    if slot is not None and hasattr(strip,'action_slot'): strip.action_slot=slot
    strip.action_frame_start=first;strip.action_frame_end=last
    strip.frame_start=scene_start;strip.scale=scale;strip.repeat=repeat
    strip.extrapolation='NOTHING';strip.blend_type=mode
    strip.use_auto_blend=False
    strip.blend_in=blend_in;strip.blend_out=blend_out
    strip.use_animated_influence=True
    end=scene_start+(last-first)*scale*repeat
    points={scene_start:strength, end:strength}
    if blend_in: points.update({scene_start:0,scene_start+blend_in:strength})
    if blend_out: points.update({end-blend_out:strength,end:0})
    for frame,value in sorted(points.items()):
        strip.influence=value;strip.keyframe_insert(data_path='influence',frame=frame)
    for curve in strip.fcurves:
        if curve.data_path=='influence':
            for point in curve.keyframe_points: point.interpolation='LINEAR'
    return strip


def apply(objects, definition):
    clips=definition.get('motion_clips',[])
    if not clips: return
    profile=definition['character_profile']
    available={item['id']:item for item in profile.get('motions',[])}
    by_rig={}
    for clip in clips:
        spec=available[clip['action_id']];rig=objects.get(spec['rig'])
        if rig is None or rig.type!='ARMATURE': raise RuntimeError('The motion rig is unavailable')
        if rig.name not in by_rig:
            by_rig[rig.name]=references(rig)
    resolved=[]
    for clip in sorted(clips,key=lambda c:(c['layer'],c['start'],c['id'])):
        spec=available[clip['action_id']];rig=objects[spec['rig']]
        match=next(((action,slot) for action,slot in by_rig[rig.name] if action.get(SOURCE_NAME,action.name)==spec['source'] and (slot.identifier if slot else '')==spec.get('slot','')),None)
        if not match: raise RuntimeError('The character action changed; reimport and register its new source')
        resolved.append((clip,spec,rig,*match))
    # Preserve source tracks as muted editable data, without mutating shared actions.
    for _,_,rig,_,_ in resolved:
        if rig.animation_data.action:
            rig.animation_data.action=None
        for track in rig.animation_data.nla_tracks: track.mute=True;track.is_solo=False
    fps=bpy.context.scene.render.fps/bpy.context.scene.render.fps_base
    for clip,spec,rig,action,slot in resolved:
        add_strip(rig,action,slot,name='LightekMotion_'+clip['id'],first=clip['source_in'],last=clip['source_out'],
                  scene_start=1+clip['start']*fps,scale=fps/spec['fps']/clip['speed'],repeat=clip['repeat'],
                  strength=clip['strength'],blend_in=clip['blend_in']*fps,blend_out=clip['blend_out']*fps,mode=clip['mode'])
