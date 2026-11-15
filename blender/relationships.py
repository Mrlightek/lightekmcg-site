"""Scene-local relative transforms, baked gaze targets and blocking checks."""
import math
import bpy
from mathutils import Matrix, Vector

def apply(objects, created):
    relations = {str(item['id']): item.get('definition', {}).get('story_relation') for item in objects if item.get('definition', {}).get('story_relation')}
    visited, visiting = set(), set()
    def visit(key):
        if key in visiting:
            raise RuntimeError('Cyclic relative parenting')
        if key in visited:
            return
        visiting.add(key)
        relation = relations.get(key, {})
        parent = relation.get('relative_to')
        if parent is not None:
            parent = str(parent)
            if parent == key or parent not in created:
                raise RuntimeError('Relative parent is unavailable')
            visit(parent)
        target = relation.get('look_at')
        if target is not None and (str(target) == key or str(target) not in created):
            raise RuntimeError('Gaze target is unavailable')
        visiting.remove(key)
        visited.add(key)
    for key in relations:
        visit(key)
    for key, relation in relations.items():
        parent = relation.get('relative_to')
        if parent is None:
            continue
        offset = relation.get('offset', [0, 0, 0])
        if len(offset) != 3 or any(not isinstance(v, (int,float)) or not math.isfinite(v) or abs(v)>1000 for v in offset):
            raise RuntimeError('Invalid relative offset')
        obj = created[key]
        obj.parent = created[str(parent)]
        obj.matrix_parent_inverse = Matrix.Identity(4)
        obj.location = tuple(offset)
    scene = bpy.context.scene
    current = scene.frame_current
    first, last = scene.frame_start, scene.frame_end
    gaze = {key: row for key,row in relations.items() if row.get('look_at') is not None}
    if gaze and last-first+1>2400:
        raise RuntimeError('Split a tracked scene into at most 2400 frames before rendering')
    markers = {}
    # Independent, baked targets let two speakers face one another without a
    # circular Blender constraint dependency. Position is sampled from the
    # authored motion before adding these new gaze constraints.
    for key in gaze:
        marker = bpy.data.objects.new('Story gaze '+key,None)
        scene.collection.objects.link(marker)
        markers[key] = marker
    for frame in range(first,last+1) if gaze else []:
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        for key, row in gaze.items():
            offset = row.get('look_at_offset',[0,0,0])
            if len(offset)!=3 or any(not math.isfinite(float(v)) or abs(float(v))>10 for v in offset):
                raise RuntimeError('Invalid gaze offset')
            target = created[str(row['look_at'])]
            markers[key].location = target.matrix_world @ Vector(offset)
            markers[key].keyframe_insert(data_path='location',frame=frame)
    for key,row in gaze.items():
        obj = created[key]
        for constraint in list(obj.constraints):
            if constraint.name == 'Lightek story focus':
                obj.constraints.remove(constraint)
        if obj.type=='CAMERA':
            constraint=obj.constraints.new('DAMPED_TRACK')
            constraint.track_axis='TRACK_NEGATIVE_Z'
        else:
            axis=row.get('facing_axis','-Y')
            if axis not in ('X','Y','-X','-Y'):
                raise RuntimeError('Invalid character forward axis')
            constraint=obj.constraints.new('LOCKED_TRACK')
            constraint.track_axis={'X':'TRACK_X','Y':'TRACK_Y','-X':'TRACK_NEGATIVE_X','-Y':'TRACK_NEGATIVE_Y'}[axis]
            constraint.lock_axis='LOCK_Z'
        constraint.name='Lightek story focus'
        constraint.target=markers[key]
        if obj.type=='CAMERA' and row.get('depth_of_field'):
            obj.data.type='PERSP'
            obj.data.dof.use_dof=True
            obj.data.dof.focus_object=markers[key]
            obj.data.dof.aperture_fstop=float(row.get('aperture_fstop',4.0))
    scene.frame_set(current)
    bpy.context.view_layer.update()
