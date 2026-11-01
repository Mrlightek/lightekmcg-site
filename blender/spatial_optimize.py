"""Isolated asset preparation; invoke with --background --disable-autoexec.
Retains original separately. Only static meshes may be decimated.
"""
import argparse,json,sys
from pathlib import Path
import bpy
sys.path.insert(0,str(Path(__file__).resolve().parent))
from spatial_asset_staging import stage_asset

def main():
    parser=argparse.ArgumentParser();parser.add_argument('source');parser.add_argument('output');parser.add_argument('--max-faces',type=int,default=100000);parser.add_argument('--texture-size',type=int,default=2048)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    if not 1000<=args.max_faces<=1000000 or not 256<=args.texture_size<=4096:raise ValueError('Invalid optimization bounds')
    bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=args.source)
    meshes=[obj for obj in bpy.context.scene.objects if obj.type=='MESH'];total=sum(len(obj.data.polygons) for obj in meshes)
    ratio=min(1,args.max_faces/max(total,1))
    for obj in meshes:
        if ratio<1 and not obj.data.shape_keys and not obj.animation_data and not any(m.type=='ARMATURE' for m in obj.modifiers):
            modifier=obj.modifiers.new('Lightek static mesh budget','DECIMATE');modifier.ratio=ratio
            bpy.context.view_layer.objects.active=obj;bpy.ops.object.modifier_apply(modifier=modifier.name)
        if not obj.data.materials:
            material=bpy.data.materials.new('Lightek PBR');material.use_nodes=True;obj.data.materials.append(material)
    for image in bpy.data.images:
        if image.size[0] and max(image.size)>args.texture_size:
            ratio=args.texture_size/max(image.size);image.scale(max(1,int(image.size[0]*ratio)),max(1,int(image.size[1]*ratio)))
    bpy.ops.export_scene.gltf(filepath=args.output,export_format='GLB')
    print(json.dumps({'meshes':len(meshes),'faces':sum(len(o.data.polygons) for o in meshes),'output':args.output}))
if __name__=='__main__':main()
