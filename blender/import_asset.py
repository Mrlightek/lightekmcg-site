"""Convert an uploaded .blend or GLB into a self-contained preview asset."""
import bpy
import sys
import os
import json
from mathutils import Vector


def main():
    args = sys.argv[sys.argv.index('--') + 1:]
    source, output, kind = args
    os.makedirs(output, exist_ok=True)
    bpy.context.preferences.filepaths.use_scripts_auto_execute = False
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    if kind == 'blend':
        with bpy.data.libraries.load(source, link=False) as (available, target):
            target.objects = available.objects
        for obj in target.objects:
            if obj is not None:
                bpy.context.collection.objects.link(obj)
    elif kind == 'glb':
        bpy.ops.import_scene.gltf(filepath=source)
    else:
        raise ValueError('Only Blender and GLB assets are supported')
    meshes = [obj for obj in bpy.context.scene.objects if obj.type == 'MESH']
    if not meshes:
        raise ValueError('The asset contains no renderable mesh')
    bpy.ops.export_scene.gltf(filepath=os.path.join(output, 'asset.glb'), export_format='GLB')
    points = [obj.matrix_world @ Vector(corner) for obj in meshes for corner in obj.bound_box]
    low = Vector(tuple(min(p[i] for p in points) for i in range(3)))
    high = Vector(tuple(max(p[i] for p in points) for i in range(3)))
    center = (low + high) / 2
    radius = max((high-low).length, 1)
    camera_data = bpy.data.cameras.new('Asset Preview Camera')
    camera = bpy.data.objects.new('Asset Preview Camera', camera_data)
    bpy.context.collection.objects.link(camera)
    camera.location = center + Vector((radius, -radius, radius * .7))
    camera.rotation_euler = (center-camera.location).to_track_quat('-Z','Y').to_euler()
    scene = bpy.context.scene
    scene.camera = camera
    light_data = bpy.data.lights.new('Asset Preview Light','AREA')
    light_data.energy = 1000 * radius
    light_data.size = radius
    light = bpy.data.objects.new('Asset Preview Light',light_data)
    bpy.context.collection.objects.link(light)
    light.location = center + Vector((0,-radius,radius))
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 8
    scene.cycles.use_denoising = False
    scene.render.resolution_x = scene.render.resolution_y = 256
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.render.filepath = os.path.join(output,'preview.png')
    bpy.ops.render.render(write_still=True)
    with open(os.path.join(output,'asset.json'),'w') as handle:
        json.dump({'mesh_count':len(meshes),'bounds':{'min':list(low),'max':list(high)},'vertices':sum(len(m.data.vertices) for m in meshes)},handle)

if __name__ == '__main__':
    main()
