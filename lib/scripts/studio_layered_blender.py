"""Build a portable, editable 2.5D project from trusted rasterized layers.

Run inside Blender with --disable-autoexec. This saves a scene, never renders it.
"""
import json
import math
from pathlib import Path
import sys
import bpy

args=sys.argv[sys.argv.index('--')+1:]
spec=json.loads(Path(args[0]).read_text());root=Path(args[1]).resolve()
canvas=spec['canvas'];width=canvas['width'];height=canvas['height'];fps=canvas['fps'];duration=canvas['duration']
layers=spec['layers'];graph=spec['composition']
if not 1<=len(layers)<=24 or not 1<=fps<=24 or not 1<=duration<=10: raise ValueError('Invalid scene bounds')
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=8
scene.cycles.transparent_max_bounces=32;scene.cycles.use_denoising=False
scene.render.threads_mode='FIXED';scene.render.threads=1
scene.render.resolution_x=width;scene.render.resolution_y=height;scene.render.resolution_percentage=100
scene.render.fps=fps;scene.frame_start=1;scene.frame_end=round(duration*fps)
scene.view_settings.view_transform='Standard'
try: scene.view_settings.look='None'
except TypeError: pass
scene.world=bpy.data.worlds.new('Lightek background');scene.world.color=(.006,.009,.014)
scene['lightek_composition_version']=1
scene['lightek_handoff']='2.5D image planes; base transforms and position tracks baked per frame'
scene['lightek_seed']=str(graph['seed'])
source=bpy.data.texts.new('Lightek scene graph.json');source.write(json.dumps(graph,indent=2))
source.use_module=False
parents={};nodes={}
def groups(items,parent=None):
    for node in items:
        nodes[node['id']]=node
        if 'children' in node:
            obj=bpy.data.objects.new(node['name'],None);scene.collection.objects.link(obj)
            obj.empty_display_type='PLAIN_AXES';obj.empty_display_size=.2;obj.parent=parent
            obj['lightek_node_id']=node['id'];obj['lightek_source_node']=json.dumps(node)
            groups(node['children'],obj)
        else: parents[node['id']]=parent
groups(graph['nodes'])
camera_data=bpy.data.cameras.new('Lightek Camera');camera=bpy.data.objects.new('Lightek Camera',camera_data)
scene.collection.objects.link(camera);scene.camera=camera;camera.location=(0,0,10)
camera_data.type='ORTHO';camera_data.sensor_fit='HORIZONTAL';camera_data.ortho_scale=width/100
camera_data.clip_start=.01;camera_data.clip_end=100

def offset(track,time):
    phase=time%track['duration']/track['duration'] if track['loop'] else min(max(time/track['duration'],0),1)
    for a,b in zip(track['keyframes'],track['keyframes'][1:]):
        if phase<=b['t']:
            blend=(phase-a['t'])/(b['t']-a['t'])
            return a['x']+(b['x']-a['x'])*blend,a['y']+(b['y']-a['y'])*blend
    raise ValueError('Invalid motion track')

for index,layer in enumerate(layers):
    path=root/f'layer-{index}.png'
    if path.is_symlink() or path.resolve().parent!=root: raise ValueError('Invalid raster source')
    image=bpy.data.images.load(str(path),check_existing=False);image.pack()
    w,h=image.size[0]/100,image.size[1]/100
    mesh=bpy.data.meshes.new(layer['id']+' plane')
    mesh.from_pydata([(-w/2,-h/2,0),(w/2,-h/2,0),(w/2,h/2,0),(-w/2,h/2,0)],[],[(0,1,2,3)]);mesh.update()
    uv=mesh.uv_layers.new(name='UVMap')
    for item,point in zip(uv.data,[(0,0),(1,0),(1,1),(0,1)]): item.uv=point
    obj=bpy.data.objects.new(layer['name'],mesh);scene.collection.objects.link(obj);obj.parent=parents[layer['id']]
    obj['lightek_node_id']=layer['id'];obj['lightek_depth']=layer['depth'];obj['lightek_layer_order']=index
    obj['lightek_asset_key']=layer.get('template','asset:'+str(layer.get('asset_id','')))
    obj['lightek_source_node']=json.dumps(nodes[layer['id']])
    material=bpy.data.materials.new(layer['name']+' image');material.use_nodes=True
    if hasattr(material,'surface_render_method'): material.surface_render_method='DITHERED'
    elif hasattr(material,'blend_method'): material.blend_method='BLEND'
    if hasattr(material,'use_transparent_shadow'): material.use_transparent_shadow=False
    tree=material.node_tree;tree.nodes.clear()
    texture=tree.nodes.new('ShaderNodeTexImage');texture.image=image;texture.interpolation='Linear';texture.extension='CLIP'
    transparent=tree.nodes.new('ShaderNodeBsdfTransparent');emission=tree.nodes.new('ShaderNodeEmission')
    mix=tree.nodes.new('ShaderNodeMixShader');output=tree.nodes.new('ShaderNodeOutputMaterial')
    tree.links.new(texture.outputs['Color'],emission.inputs['Color']);tree.links.new(texture.outputs['Alpha'],mix.inputs[0])
    tree.links.new(transparent.outputs[0],mix.inputs[1]);tree.links.new(emission.outputs[0],mix.inputs[2]);tree.links.new(mix.outputs[0],output.inputs['Surface'])
    mesh.materials.append(material)
    for frame in range(1,scene.frame_end+1):
        time=(frame-1)/fps
        moves=[offset(track,time) for track in layer.get('motions',[])]
        dx=sum(point[0] for point in moves)-spec['camera']['x']*width*layer['depth']*time/duration
        dy=sum(point[1] for point in moves)-spec['camera']['y']*height*layer['depth']*time/duration
        obj.location=((layer['x']-width/2+dx)/100,(height/2-layer['y']-dy)/100,index*.01)
        obj.keyframe_insert(data_path='location',frame=frame,group='Lightek position')
    # Blender 3.x/4.4 actions expose fcurves here; newer layered actions need slots.
    # Dense samples remain editable; linear interpolation avoids overshoot between them.
    action=obj.animation_data.action
    try:
        for curve in action.fcurves:
            for point in curve.keyframe_points: point.interpolation='LINEAR'
    except (AttributeError,RuntimeError):
        pass  # Newer action slots still retain an explicit sample on every frame.
scene.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=str(root/'scene.blend'),compress=True)
print('LIGHTEK_LAYERED_BLEND_SAVED')
