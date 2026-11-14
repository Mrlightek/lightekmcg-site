"""Native material isolation and reversible compositor proof, including real renders."""
import bpy
import json
from pathlib import Path
import sys
root,output=sys.argv[sys.argv.index('--')+1:]
sys.path.insert(0,str(Path(root)/'blender'))
import appearance
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene
bpy.ops.mesh.primitive_cube_add();obj=bpy.context.object
shader=bpy.data.materials.new('Shared source');shader.use_nodes=True
bsdf=shader.node_tree.nodes.get('Principled BSDF');bsdf.inputs['Roughness'].default_value=.7
source=shader.node_tree.nodes.new('ShaderNodeRGB');shader.node_tree.links.new(source.outputs[0],bsdf.inputs['Base Color'])
bsdf.inputs['Metallic'].default_value=.1;bsdf.inputs['Metallic'].keyframe_insert('default_value',frame=1)
bsdf.inputs['Metallic'].default_value=.6;bsdf.inputs['Metallic'].keyframe_insert('default_value',frame=12)
obj.data.materials.append(shader);obj.data.materials.append(shader)
second=obj.copy();scene.collection.objects.link(second)
appearance.material(obj,{'surface_overrides':[{'target':'','slot':1,'values':{'metallic':.8,'roughness':.2}}]})
new=obj.material_slots[1].material
assert obj.data!=second.data
assert new!=shader and obj.material_slots[0].material==shader
assert new.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].is_linked
scene.frame_set(6)
assert abs(new.node_tree.nodes.get('Principled BSDF').inputs['Metallic'].default_value-.8)<1e-5
assert abs(bsdf.inputs['Metallic'].default_value-.8)>.1
appearance.material(obj,{'surface_overrides':[{'target':'','slot':1,'values':{'color':[.4,.1,.05,1]}}]})
assert not obj.material_slots[1].material.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].is_linked
assert bsdf.inputs['Base Color'].is_linked
parent=bpy.data.objects.new('Cast root',None);scene.collection.objects.link(parent);obj.parent=parent;obj['lightek_source_object']='Face'
appearance.material(parent,{'surface_overrides':[{'target':'Face','slot':1,'values':{'roughness':.35}}]})
assert abs(obj.material_slots[1].material.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value-.35)<1e-5
scene.use_nodes=True;tree=scene.node_tree;tree.nodes.clear()
render=tree.nodes.new('CompositorNodeRLayers');native=tree.nodes.new('CompositorNodeBrightContrast');composite=tree.nodes.new('CompositorNodeComposite')
tree.links.new(render.outputs['Image'],native.inputs['Image']);tree.links.new(native.outputs['Image'],composite.inputs['Image'])
look={'exposure':1,'gamma':1.1,'saturation':1.2,'contrast':5,'blur':1,'glow':.3,'glow_threshold':1}
appearance.look(scene,look);count=len(tree.nodes)
appearance.look(scene,look);assert len(tree.nodes)==count
assert native in list(tree.nodes)
appearance.look(scene,{})
assert composite.inputs['Image'].links[0].from_node==native
assert len(tree.nodes)==3
scene.use_nodes=False;appearance.look(scene,look);appearance.look(scene,{})
assert not scene.use_nodes
# Render a visible object using the same parameter pipeline.
second.hide_render=True
for polygon in obj.data.polygons:polygon.material_index=1
bpy.ops.object.camera_add(location=(4,-6,4));camera=bpy.context.object
from mathutils import Vector
camera.rotation_euler=(Vector((0,0,0))-camera.location).to_track_quat('-Z','Y').to_euler();scene.camera=camera
bpy.ops.object.light_add(type='AREA',location=(1,-3,4));bpy.context.object.data.energy=600
scene.render.engine='CYCLES';scene.cycles.samples=4;scene.cycles.use_denoising=False
for layer in scene.view_layers:layer.cycles.use_denoising=False
scene.render.resolution_x=96;scene.render.resolution_y=96;scene.render.resolution_percentage=100
scene.render.filepath=str(Path(output)/'base.png');bpy.ops.render.render(write_still=True)
appearance.look(scene,look);scene.render.filepath=str(Path(output)/'look.png');bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=str(Path(output)/'appearance.blend'))
base_image=bpy.data.images.load(str(Path(output)/'base.png'),check_existing=False)
look_image=bpy.data.images.load(str(Path(output)/'look.png'),check_existing=False)
assert sum(abs(a-b) for a,b in zip(base_image.pixels[:],look_image.pixels[:]))>1
print('LIGHTEK_APPEARANCE_BLENDER_PASS '+json.dumps({'isolated_slots':True,'texture_preserved':True,'source_animation_preserved':True,'reversible_graph':True,'rendered':True}))
