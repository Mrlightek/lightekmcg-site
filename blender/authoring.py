"""Native authoring operations. Data commands only; imported Python never executes."""
import bpy
import bmesh
import math
from mathutils import Vector

NODE_TYPES = {
 'material': ['ShaderNodeBsdfPrincipled','ShaderNodeOutputMaterial','ShaderNodeTexNoise','ShaderNodeTexVoronoi','ShaderNodeTexChecker','ShaderNodeTexCoord','ShaderNodeMapping','ShaderNodeValToRGB','ShaderNodeMixRGB','ShaderNodeMath','ShaderNodeBump','ShaderNodeNormalMap','ShaderNodeEmission','ShaderNodeMixShader','ShaderNodeBsdfTransparent','ShaderNodeRGB','ShaderNodeValue'],
 'geometry': ['NodeGroupInput','NodeGroupOutput','GeometryNodeTransform','GeometryNodeMeshCube','GeometryNodeMeshUVSphere','GeometryNodeSetPosition','GeometryNodeInputPosition','GeometryNodeJoinGeometry','GeometryNodeSubdivisionSurface','GeometryNodeSetMaterial','GeometryNodeInstanceOnPoints','GeometryNodeRealizeInstances','GeometryNodeDistributePointsOnFaces','ShaderNodeMath','ShaderNodeVectorMath','ShaderNodeTexNoise','ShaderNodeValue'],
 'compositor': ['CompositorNodeRLayers','CompositorNodeComposite','CompositorNodeGlare','CompositorNodeBlur','CompositorNodeMixRGB','CompositorNodeColorBalance','CompositorNodeLensdist','CompositorNodeAlphaOver','CompositorNodeBrightContrast','CompositorNodeHueSat','CompositorNodeRGB','CompositorNodeValue']
}


def graph_payload(tree):
    if not tree:
        return None
    def socket_payload(s, i):
        value = getattr(s, 'default_value', None)
        if hasattr(value, 'to_list'): value = value.to_list()
        elif value is not None and not isinstance(value, (str, int, float, bool)):
            try: value = list(value)
            except TypeError: value = None
        if isinstance(value, list) and not all(isinstance(v, (float, int, bool)) for v in value): value = None
        return {'index': i, 'name': s.name, 'type': s.type, 'value': value}
    nodes = [{'name': n.name, 'type': n.bl_idname, 'label': n.label, 'location': list(n.location),
              'inputs': [socket_payload(s, i) for i, s in enumerate(n.inputs)][:64],
              'outputs': [socket_payload(s, i) for i, s in enumerate(n.outputs)][:64]} for n in list(tree.nodes)[:128]]
    names = {n['name'] for n in nodes}
    return {'name': tree.name, 'nodes': nodes, 'links': [{'from': l.from_node.name, 'output': list(l.from_node.outputs).index(l.from_socket), 'to': l.to_node.name, 'input': list(l.to_node.inputs).index(l.to_socket)} for l in tree.links if l.from_node.name in names and l.to_node.name in names][:512]}


def inventory(obj):
    data = {'authoring_version': 1, 'graphs': []}
    if obj.type == 'MESH':
        mesh = obj.data
        data['mesh'] = {'vertex_count': len(mesh.vertices), 'face_count': len(mesh.polygons), 'edge_count': len(mesh.edges),
            'vertices': [[v.index, *v.co] for v in list(mesh.vertices)[:4096]],
            'faces': [[p.index, *p.vertices] for p in list(mesh.polygons)[:4096]], 'sampled': len(mesh.vertices) > 4096 or len(mesh.polygons) > 4096}
        data['vertex_groups'] = [g.name for g in obj.vertex_groups][:256]
        if mesh.shape_keys: data['shape_keys'] = [{'name': k.name, 'value': k.value} for k in list(mesh.shape_keys.key_blocks)[:128]]
    if obj.type == 'ARMATURE':
        data['bones'] = [{'name': b.name, 'parent': b.parent.name if b.parent else None,
                         'head': list(b.head), 'tail': list(b.tail), 'location': list(b.location),
                         'rotation': list(b.rotation_euler), 'scale': list(b.scale)} for b in list(obj.pose.bones)[:512]]
    for i, slot in enumerate(obj.material_slots):
        if slot.material and slot.material.use_nodes:
            data['graphs'].append({'scope': 'material', 'slot': i, 'graph': graph_payload(slot.material.node_tree)})
    for m in obj.modifiers:
        if m.type == 'NODES' and m.node_group:
            data['graphs'].append({'scope': 'geometry', 'modifier': m.name, 'graph': graph_payload(m.node_group)})
    return data


def numbers(values, count=3):
    if not isinstance(values, list) or len(values) != count or not all(isinstance(v, (int, float)) and math.isfinite(v) and abs(v) <= 1e6 for v in values):
        raise ValueError('Invalid authoring vector')
    return values


def graph_for(obj, cmd, copies):
    scope = cmd['scope']
    if scope == 'material':
        slot = int(cmd.get('slot', 0))
        if slot < 0 or slot >= len(obj.material_slots): raise ValueError('Material slot unavailable')
        key = ('material', slot)
        if key not in copies:
            if obj.data.users > 1: obj.data = obj.data.copy()
            source = obj.material_slots[slot].material
            if source is None: raise ValueError('Material unavailable')
            obj.material_slots[slot].material = source.copy(); copies.add(key)
        material = obj.material_slots[slot].material; material.use_nodes = True
        return material.node_tree
    if scope == 'geometry':
        name = cmd.get('modifier', 'Studio Geometry')
        m = obj.modifiers.get(name)
        if m is None:
            m = obj.modifiers.new(name, 'NODES')
            group = bpy.data.node_groups.new(name, 'GeometryNodeTree')
            group.interface.new_socket(name='Geometry', in_out='INPUT', socket_type='NodeSocketGeometry')
            group.interface.new_socket(name='Geometry', in_out='OUTPUT', socket_type='NodeSocketGeometry')
            incoming = group.nodes.new('NodeGroupInput'); outgoing = group.nodes.new('NodeGroupOutput')
            group.links.new(incoming.outputs['Geometry'], outgoing.inputs['Geometry']); m.node_group = group
        if m.type != 'NODES' or m.node_group is None: raise ValueError('Geometry modifier unavailable')
        key = ('geometry', name)
        if key not in copies: m.node_group = m.node_group.copy(); copies.add(key)
        return m.node_group
    if scope == 'compositor':
        scene = bpy.context.scene; scene.use_nodes = True
        return scene.node_tree
    raise ValueError('Unsupported graph scope')


def mesh_operation(obj, cmd):
    if obj.type != 'MESH': raise ValueError('Select a mesh')
    if obj.data.users > 1: obj.data = obj.data.copy()
    mesh = obj.data
    if len(mesh.vertices) > 500000: raise ValueError('Use a mesh under 500,000 vertices for interactive editing')
    kind = cmd['kind']
    if kind == 'sculpt':
        center = Vector(numbers(cmd['center'])); delta = Vector(numbers(cmd['delta'])); radius = float(cmd['radius'])
        if not 0.001 <= radius <= 10000: raise ValueError('Invalid sculpt radius')
        centers=[center]+[Vector(numbers(point)) for point in cmd.get('path', [])]
        if len(centers)>32: raise ValueError('Use at most 32 brush samples per stroke')
        for point in centers:
            for vertex in mesh.vertices:
                distance = (vertex.co-point).length
                if distance < radius: vertex.co += delta * (1-distance/radius)**2
        mesh.update(); return
    bm = bmesh.new()
    try:
        bm.from_mesh(mesh); bm.verts.ensure_lookup_table(); bm.faces.ensure_lookup_table(); bm.edges.ensure_lookup_table()
        selection = cmd.get('indices', [])
        sequence = bm.faces if kind in ('mesh_extrude','mesh_inset','mesh_delete') else bm.edges if kind in ('mesh_bevel','mesh_subdivide') else bm.verts
        if any(i < 0 or i >= len(sequence) for i in selection): raise ValueError('Mesh selection changed; refresh its topology')
        chosen = [sequence[i] for i in selection] if selection else list(sequence)
        if kind == 'mesh_translate': bmesh.ops.translate(bm, verts=chosen, vec=Vector(numbers(cmd['delta'])))
        elif kind == 'mesh_extrude':
            region = bmesh.ops.extrude_face_region(bm, geom=chosen)
            verts = [v for v in region['geom'] if isinstance(v, bmesh.types.BMVert)]
            bmesh.ops.translate(bm, verts=verts, vec=Vector(numbers(cmd['delta'])))
        elif kind == 'mesh_subdivide': bmesh.ops.subdivide_edges(bm, edges=chosen, cuts=int(cmd['cuts']), use_grid_fill=True)
        elif kind == 'mesh_inset': bmesh.ops.inset_region(bm, faces=chosen, thickness=float(cmd['amount']), depth=0, use_even_offset=True)
        elif kind == 'mesh_bevel': bmesh.ops.bevel(bm, geom=chosen, offset=float(cmd['amount']), segments=int(cmd.get('segments', 2)), affect='EDGES')
        elif kind == 'mesh_delete': bmesh.ops.delete(bm, geom=chosen, context='FACES')
        elif kind == 'mesh_merge': bmesh.ops.remove_doubles(bm, verts=chosen, dist=float(cmd['amount']))
        elif kind == 'mesh_smooth':
            for _ in range(int(cmd.get('iterations', 1))): bmesh.ops.smooth_vert(bm, verts=chosen, factor=float(cmd.get('amount', .5)), use_axis_x=True, use_axis_y=True, use_axis_z=True)
        else: raise ValueError('Unsupported mesh operation')
        if len(bm.verts) > 500000: raise ValueError('Mesh edit exceeds the interactive geometry limit')
        bm.to_mesh(mesh); mesh.update()
    finally: bm.free()


def apply(obj, commands):
    if len(commands) > 128: raise ValueError('Authoring command limit exceeded')
    copies = set()
    if any(c['kind'] in ('keyframe','bone_pose') for c in commands) and obj.animation_data and obj.animation_data.action:
        obj.animation_data.action = obj.animation_data.action.copy()
    if any(c['kind'] == 'shape_key' for c in commands) and obj.type == 'MESH':
        obj.data = obj.data.copy()
    for cmd in commands:
        kind = cmd['kind']
        if kind.startswith('mesh_') or kind == 'sculpt': mesh_operation(obj, cmd)
        elif kind == 'modifier':
            name = cmd['name']; mod = obj.modifiers.get(name)
            if mod and mod.type != cmd['type']: raise ValueError('Modifier type mismatch')
            if not mod: mod = obj.modifiers.new(name, cmd['type'])
            properties = {'SUBSURF': {'levels','render_levels'}, 'MIRROR': {'use_clip'}, 'SOLIDIFY': {'thickness'}, 'BEVEL': {'width','segments'}, 'DECIMATE': {'ratio'}}
            for key, value in cmd.get('properties', {}).items():
                if key not in properties[cmd['type']]: raise ValueError('Invalid modifier parameter')
                setattr(mod, key, value)
        elif kind == 'bone_pose':
            if obj.type != 'ARMATURE' or cmd['bone'] not in obj.pose.bones: raise ValueError('Pose bone unavailable')
            if obj.data.users > 1: obj.data = obj.data.copy()
            bone = obj.pose.bones[cmd['bone']]; bone.rotation_mode = 'XYZ'
            bone.location = numbers(cmd.get('location', [0,0,0])); bone.rotation_euler = [math.radians(v) for v in numbers(cmd.get('rotation', [0,0,0]))]; bone.scale = numbers(cmd.get('scale', [1,1,1]))
            if 'frame' in cmd:
                for path in ('location','rotation_euler','scale'): bone.keyframe_insert(data_path=path, frame=int(cmd['frame']))
        elif kind == 'bone_add':
            if obj.type != 'ARMATURE': raise ValueError('Select an armature')
            if obj.data.users > 1: obj.data = obj.data.copy()
            bpy.ops.object.select_all(action='DESELECT'); obj.select_set(True); bpy.context.view_layer.objects.active = obj
            bpy.ops.object.mode_set(mode='EDIT')
            try:
                bone = obj.data.edit_bones.new(cmd['name']); bone.head = numbers(cmd['head']); bone.tail = numbers(cmd['tail'])
                if cmd.get('parent'): bone.parent = obj.data.edit_bones[cmd['parent']]
            finally: bpy.ops.object.mode_set(mode='OBJECT')
        elif kind == 'weight':
            if obj.type != 'MESH': raise ValueError('Select a mesh')
            if obj.data.users > 1: obj.data = obj.data.copy()
            group = obj.vertex_groups.get(cmd['group']) or obj.vertex_groups.new(name=cmd['group'])
            if any(i < 0 or i >= len(obj.data.vertices) for i in cmd['indices']): raise ValueError('Vertex selection changed')
            group.add(cmd['indices'], float(cmd['weight']), 'REPLACE')
        elif kind == 'shape_key':
            if obj.type != 'MESH' or not obj.data.shape_keys or cmd['name'] not in obj.data.shape_keys.key_blocks: raise ValueError('Shape key unavailable')
            key = obj.data.shape_keys.key_blocks[cmd['name']]; key.value = float(cmd['value'])
            if 'frame' in cmd: key.keyframe_insert(data_path='value', frame=int(cmd['frame']))
        elif kind == 'keyframe':
            frame = int(cmd['frame'])
            for key in ('location','rotation','scale'):
                if key in cmd:
                    path = 'rotation_euler' if key == 'rotation' else key
                    value = numbers(cmd[key]); setattr(obj, path, [math.radians(v) for v in value] if key == 'rotation' else value)
                    obj.keyframe_insert(data_path=path, frame=frame)
        elif kind.startswith('node_'):
            tree = graph_for(obj, cmd, copies)
            if kind == 'node_add':
                if cmd['type'] not in NODE_TYPES[cmd['scope']]: raise ValueError('Unsupported node type')
                if len(tree.nodes) >= 256: raise ValueError('Node limit exceeded')
                if tree.nodes.get(cmd['name']): raise ValueError('Node name already exists')
                node = tree.nodes.new(cmd['type']); node.name = cmd['name']; node.label = cmd['name']; node.location = cmd.get('location', [0,0])
            elif kind == 'node_link':
                source = tree.nodes[cmd['from']]; target = tree.nodes[cmd['to']]
                tree.links.new(source.outputs[int(cmd['output'])], target.inputs[int(cmd['input'])])
            elif kind == 'node_remove': tree.nodes.remove(tree.nodes[cmd['name']])
            elif kind == 'node_value':
                socket = tree.nodes[cmd['name']].inputs[int(cmd['input'])]
                if not hasattr(socket, 'default_value'): raise ValueError('Socket has no editable default')
                for link in list(socket.links): tree.links.remove(link)
                socket.default_value = cmd['value']
            else: raise ValueError('Unsupported node operation')
        else: raise ValueError('Unsupported authoring operation')
    bpy.context.view_layer.update()
