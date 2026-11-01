"""Reusable Text-to-Stage pattern; call on Blender's main thread after managed ingestion.

This module is not an HTTP/file-watcher endpoint. The coordinator supplies a prepared
local asset path and a validated command; the existing ingest worker owns dependencies.
"""
from pathlib import Path
import math
import bpy
from mathutils import Matrix, Vector


def _number(value, low, high, name):
    value = float(value)
    if not math.isfinite(value) or not low <= value <= high:
        raise ValueError(f"{name} must be between {low} and {high}")
    return value


def stage_asset(path, camera_name=None, *, screen_x=0, screen_y=0, distance=6,
                fit_fraction=0.6, color=(0.25, 0.55, 0.8, 1), name="Staged asset"):
    """Import GLB/GLTF/OBJ and fit its evaluated bounding box into a camera frame.

    screen_x/y are normalized camera-window offsets, with positive Y up. Distance
    and source geometry use Blender scene units. Existing materials are preserved;
    a Principled material is applied only where a mesh has no material.
    """
    source = Path(path).resolve(strict=True)
    if source.suffix.lower() not in {".glb", ".gltf", ".obj"}:
        raise ValueError("Use a prepared GLTF, GLB or OBJ asset")
    scene = bpy.context.scene
    camera = bpy.data.objects.get(camera_name) if camera_name else scene.camera
    if camera is None or camera.type != "CAMERA" or camera.data.type not in {"PERSP", "ORTHO"}:
        raise ValueError("Choose a perspective or orthographic staging camera")
    screen_x = _number(screen_x, -0.8, 0.8, "screen_x")
    screen_y = _number(screen_y, -0.8, 0.8, "screen_y")
    distance = _number(distance, max(camera.data.clip_start * 2, 0.01), camera.data.clip_end * 0.8, "distance")
    fit_fraction = _number(fit_fraction, 0.05, 0.9, "fit_fraction")
    if len(color) != 4:
        raise ValueError("Use an RGBA default color")
    rgba = tuple(_number(value, 0, 1, "color") for value in color)
    before = set(bpy.data.objects)
    active_camera = scene.camera
    root = None
    try:
        if source.suffix.lower() in {".glb", ".gltf"}:
            bpy.ops.import_scene.gltf(filepath=str(source))
        elif hasattr(bpy.ops.wm, "obj_import"):
            bpy.ops.wm.obj_import(filepath=str(source))
        else:  # Blender 3.x; current Lightek runtime uses Blender 4.x.
            bpy.ops.import_scene.obj(filepath=str(source))
        imported = set(bpy.data.objects) - before
        meshes = [obj for obj in imported if obj.type == "MESH"]
        if not meshes:
            raise ValueError("The imported asset has no mesh geometry to frame")
        root = bpy.data.objects.new(str(name)[:120] or "Staged asset", None)
        scene.collection.objects.link(root)
        for obj in imported:
            if obj.parent not in imported:
                original = obj.matrix_world.copy()
                obj.parent = root
                obj.matrix_world = original
        bpy.context.view_layer.update()
        depsgraph = bpy.context.evaluated_depsgraph_get()
        points = [obj.matrix_world @ Vector(corner)
                  for obj in meshes for corner in obj.evaluated_get(depsgraph).bound_box]
        minimum = Vector(tuple(min(point[i] for point in points) for i in range(3)))
        maximum = Vector(tuple(max(point[i] for point in points) for i in range(3)))
        center = (minimum + maximum) * 0.5
        if (maximum - minimum).length < 1e-8:
            raise ValueError("The asset has no usable bounding volume")
        camera_world = camera.matrix_world.normalized()
        inverse_rotation = camera_world.to_quaternion().inverted()
        offsets = [inverse_rotation @ (point - center) for point in points]
        frame = camera.data.view_frame(scene=scene)
        if camera.data.type == "PERSP":
            frame = [point * (distance / abs(point.z)) for point in frame]
        half_width = (max(point.x for point in frame) - min(point.x for point in frame)) * 0.5
        half_height = (max(point.y for point in frame) - min(point.y for point in frame)) * 0.5
        # Lens shift affects the frame center; keep the placement in that shifted window.
        frame_x = (max(point.x for point in frame) + min(point.x for point in frame)) * 0.5
        frame_y = (max(point.y for point in frame) + min(point.y for point in frame)) * 0.5
        target = Vector((frame_x + screen_x * half_width, frame_y + screen_y * half_height, -distance))
        left = max(frame_x - .95 * half_width, target.x - fit_fraction * half_width)
        right = min(frame_x + .95 * half_width, target.x + fit_fraction * half_width)
        bottom = max(frame_y - .95 * half_height, target.y - fit_fraction * half_height)
        top = min(frame_y + .95 * half_height, target.y + fit_fraction * half_height)

        def fits(scale):
            for offset in offsets:
                point = target + offset * scale
                if not camera.data.clip_start < -point.z < camera.data.clip_end:
                    return False
                factor = distance / -point.z if camera.data.type == "PERSP" else 1
                if not left <= point.x * factor <= right or not bottom <= point.y * factor <= top:
                    return False
            return True

        low, high = 0.0, 1.0
        while fits(high) and high < 1e8:
            low, high = high, high * 2
        for _ in range(40):
            mid = (low + high) * .5
            if fits(mid):
                low = mid
            else:
                high = mid
        if low <= 1e-8:
            raise ValueError("This asset cannot fit in the requested camera volume")
        target_world = camera_world @ target
        root.matrix_world = Matrix.Translation(target_world) @ Matrix.Scale(low, 4) @ Matrix.Translation(-center)
        material = None
        for mesh in meshes:
            if not mesh.data.materials or all(item is None for item in mesh.data.materials):
                if material is None:
                    material = bpy.data.materials.new("Lightek staging default")
                    material.use_nodes = True
                    principled = material.node_tree.nodes.get("Principled BSDF")
                    principled.inputs["Base Color"].default_value = rgba
                    principled.inputs["Roughness"].default_value = .55
                mesh.data.materials.clear()
                mesh.data.materials.append(material)
        bpy.context.view_layer.update()
        return {"root": root.name, "objects": sorted(obj.name for obj in imported),
                "camera": camera.name, "scale": low, "distance": distance,
                "screen": [screen_x, screen_y]}
    except Exception:
        for obj in set(bpy.data.objects) - before:
            bpy.data.objects.remove(obj, do_unlink=True)
        raise
    finally:
        scene.camera = active_camera
