"""Inspect native Blender files and produce a lightweight viewport proxy.

The packed .blend is the canonical editable/render source. GLB is a preview.
"""
import bpy
import sys
import os
import json
import math
from mathutils import Vector


def camera_payload(obj):
    camera = obj.data
    euler = obj.matrix_world.to_euler()
    return {"name": obj.name, "definition": {
        "blender_object_name": obj.name, "location": list(obj.matrix_world.translation),
        "rotation": [math.degrees(v) for v in euler], "scale": list(obj.matrix_world.to_scale()),
        "camera_type": camera.type, "fov_degrees": math.degrees(camera.angle), "lens": camera.lens, "lens_unit": camera.lens_unit,
        "sensor_fit": camera.sensor_fit, "sensor_width": camera.sensor_width, "sensor_height": camera.sensor_height,
        "shift_x": camera.shift_x, "shift_y": camera.shift_y, "clip_start": camera.clip_start, "clip_end": camera.clip_end,
        "ortho_scale": camera.ortho_scale, "dof_enabled": camera.dof.use_dof,
        "focus_distance": camera.dof.focus_distance, "focus_object_name": camera.dof.focus_object.name if camera.dof.focus_object else None,
        "aperture_fstop": camera.dof.aperture_fstop, "aperture_blades": camera.dof.aperture_blades,
        "aperture_rotation": math.degrees(camera.dof.aperture_rotation), "aperture_ratio": camera.dof.aperture_ratio,
        "panorama_type": getattr(getattr(camera, 'cycles', camera), 'panorama_type', 'EQUIRECTANGULAR'),
        **{key: math.degrees(getattr(camera,key)) for key in ('fisheye_fov','latitude_min','latitude_max','longitude_min','longitude_max') if hasattr(camera,key)},
        **{key:getattr(camera,key) for key in ('fisheye_lens','fisheye_polynomial_k0','fisheye_polynomial_k1','fisheye_polynomial_k2','fisheye_polynomial_k3','fisheye_polynomial_k4') if hasattr(camera,key)},
        **{'stereo_'+key:getattr(camera.stereo,key) for key in ('convergence_mode','pivot','interocular_distance','convergence_distance')}}}


def scene_payload(scene):
    return {"name": scene.name, "active_camera": scene.camera.name if scene.camera else None,
        "settings": {"render_engine": scene.render.engine, "resolution_x": scene.render.resolution_x,
          "resolution_y": scene.render.resolution_y, "resolution_percentage": scene.render.resolution_percentage,
          "transparent_background": scene.render.film_transparent, "fps": scene.render.fps,
          "fps_base": scene.render.fps_base, "frame_start": scene.frame_start, "frame_end": scene.frame_end,
          "frame_current": scene.frame_current},
        "cameras": [camera_payload(obj) for obj in scene.objects if obj.type == 'CAMERA'],
        "object_count": len(scene.objects), "collection_count": len(scene.collection.children),
        "armature_count": sum(obj.type == 'ARMATURE' for obj in scene.objects),
        "geometry_nodes_count": sum(mod.type == 'NODES' for obj in scene.objects for mod in obj.modifiers),
        "animation_count": sum(bool(obj.animation_data) for obj in scene.objects),
        "compositor": scene.use_nodes, "world": scene.world.name if scene.world else None}


def main():
    source, output, kind = sys.argv[sys.argv.index('--') + 1:]
    os.makedirs(output, exist_ok=True)
    bpy.context.preferences.filepaths.use_scripts_auto_execute = False
    if kind == 'blend':
        bpy.ops.wm.open_mainfile(filepath=source, load_ui=False, use_scripts=False)
    elif kind == 'glb':
        bpy.ops.object.select_all(action='SELECT')
        bpy.ops.object.delete(use_global=False)
        bpy.ops.import_scene.gltf(filepath=source)
    else:
        raise ValueError('Only Blender and GLB assets are supported')
    source_version = list(bpy.data.version)
    if kind == 'blend' and tuple(source_version[:2]) > tuple(bpy.app.version[:2]):
        raise RuntimeError('This template requires Blender %s.%s or newer; the worker is %s' % (source_version[0],source_version[1],bpy.app.version_string))
    scenes = [scene_payload(scene) for scene in bpy.data.scenes]
    missing = []
    for image in bpy.data.images:
        if image.source == 'FILE' and image.filepath and not image.packed_file:
            path = bpy.path.abspath(image.filepath, library=image.library)
            if not os.path.isfile(path):
                missing.append(os.path.basename(image.filepath))
    for path in bpy.utils.blend_paths(absolute=True, packed=False):
        if path and not os.path.exists(path):
            missing.append(os.path.basename(path))
    missing = sorted(set(missing))
    readmes = [{"name": text.name, "text": text.as_string()[:16000]} for text in bpy.data.texts if 'readme' in text.name.lower() or 'license' in text.name.lower() or 'credit' in text.name.lower()]
    if kind == 'blend':
        try:
            bpy.ops.file.pack_all()
            if bpy.data.libraries:
                bpy.ops.file.pack_libraries()
        except RuntimeError:
            pass
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(output, 'native.blend'), check_existing=False, compress=True, relative_remap=False)
    scene = bpy.context.scene
    original_scene = scene.name
    metadata={"native_blender":kind=='blend',"blender_version":bpy.app.version_string,"source_blender_version":source_version,"source_scene":original_scene,
        "scenes":scenes,"readmes":readmes,"missing_dependencies":missing,"warnings":[]}
    with open(os.path.join(output,'asset.json'),'w',encoding='utf-8') as handle:
        json.dump(metadata,handle,ensure_ascii=False)
    meshes = [obj for obj in scene.objects if obj.type in {'MESH', 'CURVE', 'SURFACE', 'META', 'FONT', 'VOLUME', 'GPENCIL', 'GREASEPENCIL'}]
    warnings = []
    try:
        bpy.ops.export_scene.gltf(filepath=os.path.join(output, 'asset.glb'), export_format='GLB', export_cameras=True)
    except Exception as error:
        warnings.append('Viewport proxy is unavailable: ' + str(error)[:400])
    # Thumbnail settings affect only the process after native.blend was saved.
    points = [obj.matrix_world @ Vector(corner) for obj in meshes for corner in getattr(obj, 'bound_box', [])]
    center = Vector((0, 0, 0))
    radius = 4
    if points:
        low = Vector(tuple(min(p[i] for p in points) for i in range(3)))
        high = Vector(tuple(max(p[i] for p in points) for i in range(3)))
        center, radius = (low + high) / 2, max((high-low).length, 1)
    # Use a native camera when available; create a thumbnail-only camera otherwise.
    if not scene.camera:
        data = bpy.data.cameras.new('Lightek Thumbnail Camera')
        camera = bpy.data.objects.new(data.name, data)
        scene.collection.objects.link(camera)
        camera.location = center + Vector((radius, -radius, radius * .7))
        camera.rotation_euler = (center-camera.location).to_track_quat('-Z','Y').to_euler()
        scene.camera = camera
    if not any(obj.type == 'LIGHT' for obj in scene.objects):
        data = bpy.data.lights.new('Lightek Thumbnail Light', 'AREA');data.energy=1000*radius;data.size=radius
        light=bpy.data.objects.new(data.name,data);scene.collection.objects.link(light);light.location=center+Vector((0,-radius,radius))
    scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=2;scene.cycles.use_denoising=False
    scene.render.resolution_x=scene.render.resolution_y=256;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG';scene.render.filepath=os.path.join(output,'preview.png')
    try:
        bpy.ops.render.render(write_still=True)
    except Exception as error:
        warnings.append('Thumbnail is unavailable: ' + str(error)[:400])
    metadata={"native_blender":kind=='blend',"blender_version":bpy.app.version_string,"source_blender_version":source_version,"source_scene":original_scene,
        "scenes":scenes,"mesh_count":len(meshes),"readmes":readmes,"missing_dependencies":missing,"warnings":warnings}
    with open(os.path.join(output,'asset.json'),'w',encoding='utf-8') as handle:
        json.dump(metadata,handle,ensure_ascii=False)


if __name__ == '__main__':
    main()
