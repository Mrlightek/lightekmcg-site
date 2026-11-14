"""Saved material inputs and a reversible compositor finish over the native graph."""
import bpy

SOCKETS={'color':'Base Color','metallic':'Metallic','roughness':'Roughness','transmission':'Transmission Weight','ior':'IOR','opacity':'Alpha','emission_color':'Emission Color','emission_strength':'Emission Strength'}
TAG='lightek_scene_look'


def material(root, definition):
    for override in definition.get('surface_overrides',[]):
        target=override['target']
        candidates=[root] if not target else [obj for obj in root.children_recursive if obj.get('lightek_source_object')==target]
        if len(candidates)!=1: raise RuntimeError('The selected material mesh is unavailable')
        obj=candidates[0];slot=override['slot']
        if not hasattr(obj.data,'materials') or slot>=len(obj.material_slots) or not obj.material_slots[slot].material:
            raise RuntimeError('The selected material slot is unavailable')
        obj.data=obj.data.copy()
        shader=obj.material_slots[slot].material.copy();obj.data.materials[slot]=shader;shader.use_nodes=True
        bsdf=shader.node_tree.nodes.get('Principled BSDF')
        if bsdf is None: raise RuntimeError('The selected Principled material is unavailable')
        animation=shader.node_tree.animation_data
        if animation and animation.action: animation.action=animation.action.copy()
        for field,value in override['values'].items():
            socket=bsdf.inputs.get(SOCKETS[field])
            if socket is None: raise RuntimeError('The selected material input is unavailable')
            for link in list(socket.links): shader.node_tree.links.remove(link)
            # Explicit input edits replace that input's source animation as well as links.
            path=socket.path_from_id('default_value');animation=shader.node_tree.animation_data
            if animation:
                action=animation.action
                collections=[action.fcurves] if action and hasattr(action,'fcurves') else [bag.fcurves for layer in getattr(action,'layers',[]) for strip in layer.strips for bag in getattr(strip,'channelbags',[])]
                for curves in collections:
                    for curve in list(curves):
                        if curve.data_path==path: curves.remove(curve)
                for curve in list(animation.drivers):
                    if curve.data_path==path: shader.node_tree.driver_remove(path)
            socket.default_value=value
            if field=='color': shader.diffuse_color=value
        if override['values'].get('opacity',1)<1:
            if hasattr(shader,'surface_render_method'):shader.surface_render_method='DITHERED'
            elif hasattr(shader,'blend_method'):shader.blend_method='BLEND'


def clear_look(scene):
    tree=scene.node_tree
    if not tree:return
    managed=[node for node in tree.nodes if node.get(TAG)]
    entry=next((node for node in managed if node.get(TAG)=='input'),None)
    if entry:
        source=entry.inputs[0].links[0].from_socket if entry.inputs[0].is_linked else None
        if entry.get('was_linked') and source:
            for node in tree.nodes:
                if node.type=='COMPOSITE' and node.inputs['Image'].is_linked and node.inputs['Image'].links[0].from_node in managed:
                    tree.links.new(source,node.inputs['Image'])
        original_use=bool(entry.get('original_use',True))
    else: original_use=scene.use_nodes
    for node in managed:tree.nodes.remove(node)
    scene.use_nodes=original_use


def look(scene, values):
    clear_look(scene)
    if not values or all(values.get(name,default)==default for name,default in [('exposure',0),('gamma',1),('saturation',1),('contrast',0),('blur',0),('glow',0)]): return
    original=scene.use_nodes;scene.use_nodes=True;tree=scene.node_tree
    composite=next((node for node in tree.nodes if node.type=='COMPOSITE' and getattr(node,'is_active_output',False)),None) or next((node for node in tree.nodes if node.type=='COMPOSITE'),None)
    if not composite:
        composite=tree.nodes.new('CompositorNodeComposite');composite[TAG]='output'
    linked=composite.inputs['Image'].is_linked
    prior=composite.inputs['Image'].links[0].from_socket if linked else None
    if prior is None:
        source=tree.nodes.new('CompositorNodeRLayers');source[TAG]='source';prior=source.outputs['Image']
    entry=tree.nodes.new('NodeReroute');entry[TAG]='input';entry['original_use']=original;entry['was_linked']=linked
    tree.links.new(prior,entry.inputs[0]);prior=entry.outputs[0]
    def add(kind,label):
        nonlocal prior
        node=tree.nodes.new(kind);node[TAG]='effect';node.label='Lightek · '+label
        tree.links.new(prior,node.inputs['Image']);prior=node.outputs['Image'];return node
    if values.get('exposure',0):add('CompositorNodeExposure','Exposure').inputs['Exposure'].default_value=values['exposure']
    if values.get('gamma',1)!=1:add('CompositorNodeGamma','Gamma').inputs['Gamma'].default_value=values['gamma']
    if values.get('saturation',1)!=1:add('CompositorNodeHueSat','Saturation').inputs['Saturation'].default_value=values['saturation']
    if values.get('contrast',0):add('CompositorNodeBrightContrast','Contrast').inputs['Contrast'].default_value=values['contrast']
    if values.get('blur',0):
        node=add('CompositorNodeBlur','Blur');node.filter_type='GAUSS';node.size_x=node.size_y=int(round(values['blur']))
    if values.get('glow',0):
        node=add('CompositorNodeGlare','Glow');node.glare_type='FOG_GLOW';node.quality='MEDIUM'
        if node.inputs.get('Threshold'):node.inputs['Threshold'].default_value=values.get('glow_threshold',1)
        else:node.threshold=values.get('glow_threshold',1)
        if node.inputs.get('Strength'):node.inputs['Strength'].default_value=values['glow']
        else:node.mix=values['glow']-1
    tree.links.new(prior,composite.inputs['Image'])
