#!/usr/bin/env python3
"""Prepare a textured FBX or render a Mixamo animation with a studio camera."""
import argparse
import os
from pathlib import Path
import sys
from math import ceil, floor, radians, tan

import bpy
from mathutils import Vector


RESOLUTIONS = {"640x360": (640, 360), "1280x720": (1280, 720), "720x720": (720, 720)}
COLOR_INPUTS = ("Base Color", "Emission Color", "Emission")
DATA_INPUTS = ("Roughness", "Metallic", "Normal", "Coat Normal", "Alpha",
               "Specular IOR Level", "Transmission Weight")


def texture_index(roots):
    files = {}
    for root in roots:
        if root.is_dir():
            for path in sorted(root.rglob("*")):
                if path.is_file():
                    files.setdefault(path.name.casefold(), []).append(path)
    return files


def source_nodes(socket, seen=None):
    if seen is None:
        seen = set()
    for link in socket.links:
        node = link.from_node
        if node in seen:
            continue
        seen.add(node)
        if node.type == "TEX_IMAGE":
            yield node
        else:
            for upstream in node.inputs:
                yield from source_nodes(upstream, seen)


def repair_image(node, files):
    image = node.image
    if image is None:
        return False
    if image.packed_file or image.has_data:
        return True

    basename = Path(image.filepath.replace("\\", "/")).name.casefold()
    candidates = files.get(basename, [])
    if len(candidates) == 1:
        image.filepath = str(candidates[0])
    try:
        image.reload()
        return bool(image.size[0] and image.size[1])
    except RuntimeError:
        return False


def split_direct_color_links(tree, shader):
    """Keep a color read independent from a data read of the same texture."""
    data_nodes = {image for name in DATA_INPUTS if name != "Alpha"
                  for socket in [shader.inputs.get(name)] if socket
                  for image in source_nodes(socket)}
    for name in COLOR_INPUTS:
        socket = shader.inputs.get(name)
        if socket is None or not socket.is_linked:
            continue
        link = socket.links[0]
        original = link.from_node
        if original not in data_nodes:
            continue
        texture = tree.nodes.new("ShaderNodeTexImage")
        texture.image = original.image
        texture.interpolation = original.interpolation
        texture.extension = original.extension
        texture.projection = original.projection
        texture.projection_blend = original.projection_blend
        texture.inputs["Vector"].default_value = original.inputs["Vector"].default_value
        for vector_link in original.inputs["Vector"].links:
            tree.links.new(vector_link.from_socket, texture.inputs["Vector"])
        texture.location = original.location + Vector((0, -320))
        output = link.from_socket.name
        tree.links.remove(link)
        tree.links.new(texture.outputs[output], socket)


def sanitize_materials(meshes, files):
    materials = {slot.material for mesh in meshes for slot in mesh.material_slots if slot.material}
    images_by_role = {}
    repaired_images = {}
    for material in materials:
        if not material.use_nodes:
            material.use_nodes = True
            principled = next((node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED"), None)
            if principled:
                principled.inputs["Base Color"].default_value = material.diffuse_color
                principled.inputs["Metallic"].default_value = material.metallic
                principled.inputs["Roughness"].default_value = material.roughness
        tree = material.node_tree
        if tree is None:
            continue
        for shader in [node for node in tree.nodes if node.type == "BSDF_PRINCIPLED"]:
            split_direct_color_links(tree, shader)
            for name in (*COLOR_INPUTS, *DATA_INPUTS):
                socket = shader.inputs.get(name)
                if socket is None:
                    continue
                nodes = list(source_nodes(socket))
                available = []
                for node in nodes:
                    if node not in repaired_images:
                        repaired_images[node] = repair_image(node, files)
                    if repaired_images[node]:
                        available.append(node)
                if nodes and not available:
                    for link in list(socket.links):
                        tree.links.remove(link)
                for node in available:
                    # Alpha uses the raw alpha channel even on an sRGB texture.
                    if name == "Alpha" and node.outputs["Alpha"].is_linked:
                        continue
                    color_space = "sRGB" if name in COLOR_INPUTS else "Non-Color"
                    original = node.image
                    roles = images_by_role.setdefault(original, {})
                    if color_space not in roles:
                        image = original.copy() if roles else original
                        image.colorspace_settings.name = color_space
                        roles[color_space] = image
                    node.image = roles[color_space]

            base = shader.inputs["Base Color"]
            if not base.is_linked and max(base.default_value[:3]) < 0.015:
                diffuse = tuple(material.diffuse_color)
                fallback = diffuse[:3] if max(diffuse[:3]) >= 0.015 else (0.30, 0.25, 0.21)
                base.default_value = (*fallback, 1.0)
            metallic = shader.inputs["Metallic"]
            if not metallic.is_linked and metallic.default_value >= 0.85:
                metallic.default_value = 0.12
            roughness = shader.inputs["Roughness"]
            if not roughness.is_linked and roughness.default_value < 0.18:
                roughness.default_value = 0.48

    print(f"[blender] Checked {len(materials)} imported materials", flush=True)


def track(obj, target):
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def light(scene, name, target, offset, size, power, scale):
    data = bpy.data.lights.new(name, "AREA")
    data.energy = power * scale ** 2
    data.shape = "DISK"
    data.size = size * scale
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.location = target + Vector(offset) * scale
    track(obj, target)


def set_stage(scene, center, extent):
    height = max(extent.z, extent.x / 2, 0.01)
    scene.world = bpy.data.worlds.new("Studio ambient")
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.20, 0.24, 0.32, 1)
    background.inputs["Strength"].default_value = 0.45

    bpy.ops.mesh.primitive_plane_add(size=height * 200,
        location=(center.x, center.y, center.z - extent.z / 2 - height * 0.01))
    floor_material = bpy.data.materials.new("Studio floor")
    floor_material.use_nodes = True
    floor_shader = floor_material.node_tree.nodes.get("Principled BSDF")
    floor_shader.inputs["Base Color"].default_value = (0.055, 0.070, 0.095, 1)
    floor_shader.inputs["Roughness"].default_value = 0.78
    bpy.context.object.data.materials.append(floor_material)

    camera_data = bpy.data.cameras.new("Studio camera")
    camera = bpy.data.objects.new("Studio camera", camera_data)
    scene.collection.objects.link(camera)
    direction = Vector((0.20, -1, 0.15)).normalized()
    camera.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
    rotation = camera.rotation_euler.to_matrix()
    right, up = rotation @ Vector((1, 0, 0)), rotation @ Vector((0, 1, 0))
    half = extent / 2
    aspect = scene.render.resolution_x / scene.render.resolution_y
    horizontal = tan(radians(22))
    distance = max(sum(abs(right[i]) * half[i] for i in range(3)) / horizontal,
                   sum(abs(up[i]) * half[i] for i in range(3)) * aspect / horizontal)
    distance = distance * 1.18 + sum(abs(direction[i]) * half[i] for i in range(3))
    camera.location = center + direction * distance
    camera_data.sensor_fit = "HORIZONTAL"
    camera_data.angle = radians(44)
    camera_data.clip_start = height * 0.001
    camera_data.clip_end = distance + height * 250
    scene.camera = camera
    light(scene, "Key", center, (1.35, -1.7, 1.65), 1.5, 1000, height)
    light(scene, "Fill", center, (-1.2, -1.1, 0.7), 1.8, 340, height)
    light(scene, "Rim", center, (0.4, 1.25, 1.55), 1.2, 830, height)


def animation_range(scene, meshes):
    armatures = [obj for obj in scene.objects if obj.type == "ARMATURE"]
    actions = [arm.animation_data.action for arm in armatures
               if arm.animation_data and arm.animation_data.action]
    if not meshes or not actions:
        raise RuntimeError("Animated FBX must contain meshes and an animated armature")
    start = min(floor(action.frame_range[0] + 0.0001) for action in actions)
    stop = max(ceil(action.frame_range[1] - 0.0001) for action in actions)
    return start, max(start, stop)


def bounds(scene, meshes, start, stop):
    minimum = Vector((float("inf"),) * 3)
    maximum = Vector((-float("inf"),) * 3)
    for frame in sorted({start + round((stop - start) * index / 12) for index in range(13)}):
        scene.frame_set(frame)
        depsgraph = bpy.context.evaluated_depsgraph_get()
        for mesh in meshes:
            obj = mesh.evaluated_get(depsgraph)
            for coordinate in obj.bound_box:
                point = obj.matrix_world @ Vector(coordinate)
                for axis in range(3):
                    minimum[axis] = min(minimum[axis], point[axis])
                    maximum[axis] = max(maximum[axis], point[axis])
    return (minimum + maximum) / 2, maximum - minimum


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--character", type=Path, required=True)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--pack-fbx", type=Path)
    modes.add_argument("--output-dir", type=Path)
    parser.add_argument("--texture-dir", type=Path, action="append", default=[])
    parser.add_argument("--frames", type=int, default=30)
    parser.add_argument("--resolution", choices=RESOLUTIONS, default="640x360")
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    args = parser.parse_args(argv)
    if not 1 <= args.frames <= 900:
        parser.error("--frames must be between 1 and 900")
    return args


def main():
    args = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = 30
    scene.render.fps_base = 1.0
    if "FINISHED" not in bpy.ops.import_scene.fbx(filepath=str(args.character.resolve()), use_image_search=False):
        raise RuntimeError("Blender could not import the FBX")
    meshes = [obj for obj in scene.objects if obj.type == "MESH"]
    source_dir = args.character.resolve().parent
    fbx_textures = source_dir / (args.character.stem + ".fbm")
    sanitize_materials(meshes, texture_index([source_dir / "textures", fbx_textures, *args.texture_dir]))

    if args.pack_fbx:
        if not meshes or not any(obj.type == "ARMATURE" for obj in scene.objects):
            raise RuntimeError("MakeHuman FBX must contain meshes and an armature")
        bpy.ops.export_scene.fbx(filepath=str(args.pack_fbx.resolve()),
            object_types={"ARMATURE", "MESH"}, path_mode="COPY", embed_textures=True,
            add_leaf_bones=False, bake_anim=False)
        return

    start, stop = animation_range(scene, meshes)
    scene.render.resolution_x, scene.render.resolution_y = RESOLUTIONS[args.resolution]
    scene.render.resolution_percentage = 100
    set_stage(scene, *bounds(scene, meshes, start, min(stop, start + args.frames - 1)))
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    import _cycles

    denoising = bool(getattr(_cycles, "with_openimagedenoise", False))
    scene.cycles.samples = 8 if denoising else 24
    scene.cycles.use_denoising = denoising
    if denoising:
        scene.cycles.denoiser = "OPENIMAGEDENOISE"
    scene.render.threads_mode = "FIXED"
    scene.render.threads = min(len(os.sched_getaffinity(0)), 4) if hasattr(os, "sched_getaffinity") else 4
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    args.output_dir.mkdir(parents=True, exist_ok=True)

    for index in range(args.frames):
        scene.frame_set(start + index % (stop - start + 1))
        frame_file = (args.output_dir / f"frame_{index + 1:06d}.png").resolve()
        scene.render.filepath = str(frame_file)
        if "FINISHED" not in bpy.ops.render.render(write_still=True) or not frame_file.is_file():
            raise RuntimeError(f"Blender did not write render frame {index + 1}")
    print(f"[blender] Rendered {args.frames} frames", flush=True)


if __name__ == "__main__":
    main()
