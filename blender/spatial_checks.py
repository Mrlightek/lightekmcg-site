"""Frame-sampled geometric validation, not a rigid-body dynamics solver."""
import math
import bpy
from mathutils.bvhtree import BVHTree

def geometry(root, depsgraph, exclude=()):
    vertices, triangles = [], []
    for obj in [root]+list(root.children_recursive):
        if obj.type!='MESH' or obj in exclude:
            continue
        evaluated=obj.evaluated_get(depsgraph)
        mesh=evaluated.to_mesh()
        try:
            mesh.calc_loop_triangles()
            start=len(vertices)
            vertices.extend(evaluated.matrix_world @ vertex.co for vertex in mesh.vertices)
            triangles.extend(tuple(start+v for v in triangle.vertices) for triangle in mesh.loop_triangles)
        finally:
            evaluated.to_mesh_clear()
    if not vertices or not triangles:
        return None
    bounds=[(min(v[axis] for v in vertices),max(v[axis] for v in vertices)) for axis in range(3)]
    return vertices,triangles,bounds

def intersects(a,b):
    if any(a[2][axis][1]<b[2][axis][0]-0.0001 or b[2][axis][1]<a[2][axis][0]-0.0001 for axis in range(3)):
        return False
    # Flat horizontal ground contact is allowed, penetration below it is not.
    if b[2][2][1]-b[2][2][0]<0.001:
        return a[2][2][0]<b[2][2][1]-0.01
    tree_a=BVHTree.FromPolygons(a[0],a[1],all_triangles=True)
    tree_b=BVHTree.FromPolygons(b[0],b[1],all_triangles=True)
    if tree_a.overlap(tree_b):
        return True
    # Also detect a solid fully enclosing another solid. The first outward
    # surface hit has a normal facing along the ray from an interior point.
    from mathutils import Vector
    direction=Vector((1.0,0.371,0.127)).normalized()
    hit,normal,_,_=tree_b.ray_cast(a[0][0]+direction*0.0001,direction)
    return hit is not None and normal.dot(direction)>0.001

def validate(objects,created,settings,contacts=()):
    direction=settings.get('spatial_direction') or {}
    cast=[item for item in objects if (item.get('definition',{}).get('director_speaker') or item.get('definition',{}).get('blocking_actor') or item.get('definition',{}).get('character_profile')) and str(item['id']) in created]
    if not cast:
        return
    scene=bpy.context.scene
    scene.unit_settings.system='METRIC'
    scene.unit_settings.scale_length=1.0
    current=scene.frame_current
    if scene.frame_end-scene.frame_start+1>2400:
        raise RuntimeError('Split spatially validated scenes into at most 2400 frames')
    personal=float(direction.get('personal_space',0.9))
    if not math.isfinite(personal) or not 0<=personal<=5:
        raise RuntimeError('Invalid personal-space radius')
    colliders=[item for item in objects if str(item['id']) in created and item not in cast and item.get('type') not in ('camera','area_light','point_light','sun_light','spot_light') and not item.get('definition',{}).get('native_deleted')]
    for frame in range(scene.frame_start,scene.frame_end+1):
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        depsgraph=bpy.context.evaluated_depsgraph_get()
        cache={}
        def mesh(item):
            key=str(item['id'])
            if key not in cache:
                cache[key]=geometry(created[key],depsgraph)
            return cache[key]
        for index,item in enumerate(cast):
            root=created[str(item['id'])]
            relation=item.get('definition',{}).get('story_relation',{})
            definition=item.get('definition',{})
            binding=definition.get('character_profile',{}).get('bones',{}).get('head')
            focus=root.constraints.get('Lightek story focus')
            if binding and focus and focus.target:
                rig=next((obj for obj in root.children_recursive if obj.get('lightek_source_object')==binding['object']),None)
                if rig is None or rig.type!='ARMATURE' or binding['bone'] not in rig.pose.bones:
                    raise RuntimeError('The bound head for gaze validation is unavailable')
                bone=rig.pose.bones[binding['bone']]
                from mathutils import Vector
                axis={'X':(1,0,0),'Y':(0,1,0),'-X':(-1,0,0),'-Y':(0,-1,0)}[relation.get('facing_axis','-Y')]
                root_forward=root.matrix_world.to_quaternion() @ Vector(axis)
                rest_world=rig.matrix_world.to_quaternion() @ bone.bone.matrix_local.to_quaternion()
                local_forward=rest_world.inverted() @ root_forward
                facing=rig.matrix_world.to_quaternion() @ (bone.matrix.to_quaternion() @ local_forward)
                origin=rig.matrix_world @ bone.head
                target=focus.target.matrix_world.translation-origin
                if target.length<0.01 or facing.normalized().dot(target.normalized())<math.cos(math.radians(30)):
                    raise RuntimeError('Head eyeline mismatch at frame '+str(frame)+': '+item['name']+'. Correct the head pose or listener target.')
            for other in cast[index+1:]:
                other_relation=other.get('definition',{}).get('story_relation',{})
                distance=(root.matrix_world.translation-created[str(other['id'])].matrix_world.translation).length
                desired=max(personal,float(relation.get('personal_space',personal)),float(other_relation.get('personal_space',personal)))
                close=relation.get('allow_close_contact') and other_relation.get('allow_close_contact')
                if distance<desired and not close:
                    raise RuntimeError('Personal-space violation at frame '+str(frame)+': '+item['name']+' / '+other['name'])
                if direction.get('collision_detection',True) and mesh(item) and mesh(other) and intersects(mesh(item),mesh(other)):
                    raise RuntimeError('Character collision at frame '+str(frame)+': '+item['name']+' / '+other['name'])
            if direction.get('collision_detection',True) and mesh(item):
                for other in colliders:
                    active=[cue for cue in contacts if cue['actor_id']==str(item['id']) and cue['target_id']==str(other['id']) and cue['first']<=frame<=cue['last']]
                    body=geometry(root,depsgraph,exclude=[cue['hand'] for cue in active]) if active else mesh(item)
                    if body and mesh(other) and intersects(body,mesh(other)):
                        raise RuntimeError('Environment collision at frame '+str(frame)+': '+item['name']+' / '+other['name'])
                    for cue in active:
                        hand_mesh=geometry(cue['hand'],depsgraph)
                        if hand_mesh and mesh(other) and intersects(hand_mesh,mesh(other)):
                            target=created[str(other['id'])];plane=target.matrix_world @ cue['point'];normal=(target.matrix_world.to_quaternion() @ cue['normal']).normalized()
                            if min((vertex-plane).dot(normal) for vertex in hand_mesh[0]) < -0.002:
                                raise RuntimeError('Hand penetrates its contact prop at frame '+str(frame))
    scene.frame_set(current)
    bpy.context.view_layer.update()
