"""Shared Blender scene, animation, camera, and render functions."""
import json
import logging
import math
import os
from pathlib import Path
import struct
import sys
import tempfile
from types import ModuleType

import bpy
from mathutils import Vector


LOG = logging.getLogger("lightek.render")
ENGINES = {"EEVEE": "BLENDER_EEVEE_NEXT", "CYCLES": "CYCLES"}
LIGHTING = {"studio_soft", "dramatic_rim", "outdoor_day"}
MAX_FRAMES = 1_048_574


class JobError(Exception):
    """A job failed with an actionable error for the caller."""


def require(condition, field, message):
    if not condition:
        raise JobError(f"{field}: {message}")


def number(value, field):
    # Blender's transform and animation RNA properties use single precision.
    valid = type(value) in (int, float) and -3.402823466e38 <= value <= 3.402823466e38
    require(valid, field, "expected a finite number representable by Blender")


def integer(value, field, minimum, maximum):
    number(value, field)
    require(value == int(value) and minimum <= value <= maximum,
            field, f"expected an integer between {minimum} and {maximum}")
    return int(value)


def check_glb(path):
    """Check the GLB container and require embedded buffers and textures."""
    try:
        with path.open("rb") as source:
            magic, version, total_size = struct.unpack("<4sII", source.read(12))
            json_size, chunk_type = struct.unpack("<I4s", source.read(8))
            if (magic != b"glTF" or version != 2 or total_size != os.fstat(source.fileno()).st_size
                    or chunk_type != b"JSON" or json_size % 4 or json_size > total_size - 20):
                raise ValueError("invalid GLB 2.0 header")
            data = json.loads(source.read(json_size))
        for entry in (*data.get("buffers", []), *data.get("images", [])):
            uri = entry.get("uri")
            if uri is not None and (not isinstance(uri, str) or not uri.startswith("data:")):
                raise ValueError("external buffer or texture URI; embed it in the GLB")
    except (OSError, ValueError, AttributeError, TypeError, struct.error) as error:
        raise JobError(f"Invalid asset {path}: {error}") from error


def animation_owners(objects):
    """Include object, rig, shape-key, and material animation within this import."""
    owners = set(objects)
    for obj in objects:
        if obj.data is not None:
            owners.add(obj.data)
            shape_keys = getattr(obj.data, "shape_keys", None)
            if shape_keys is not None:
                owners.add(shape_keys)
        for slot in obj.material_slots:
            if slot.material is not None:
                owners.add(slot.material)
                if slot.material.node_tree is not None:
                    owners.add(slot.material.node_tree)
    return sorted((owner for owner in owners if getattr(owner, "animation_data", None)),
                  key=lambda owner: (owner.bl_rna.identifier, owner.name))


def set_strip_timing(strip, clip_end, frame_count, loop):
    # glTF samples are imported in frames starting at time zero. Use one
    # clip duration for every channel, including owners with shorter curves.
    strip.action_frame_start = 0.0
    strip.action_frame_end = clip_end
    strip.frame_start = 1.0
    strip.frame_end = float(frame_count + 1)
    strip.blend_type = "REPLACE"
    strip.extrapolation = "HOLD_FORWARD"
    strip.use_animated_time = True
    strip.use_animated_time_cyclic = loop
    if loop:
        time_keys = [(1, 0.0), (frame_count + 1, float(frame_count))]
    else:
        time_keys = [(1, 0.0), (1 + clip_end, clip_end)]
    for scene_frame, action_frame in time_keys:
        strip.strip_time = action_frame
        strip.keyframe_insert(data_path="strip_time", frame=scene_frame)
    for curve in strip.fcurves:
        if curve.data_path == "strip_time":
            for key in curve.keyframe_points:
                key.interpolation = "LINEAR"


def activate_animation(owners, item, frame_count, track_names):
    clip = item["animationClip"]
    track_name = track_names.get(clip, clip)
    named_tracks = []
    named_actions = []
    available = set(track_names)
    for owner in owners:
        data = owner.animation_data
        for track in data.nla_tracks:
            track.mute = True
            track.is_solo = False
            strips = [strip for strip in track.strips if strip.action is not None]
            if not strips:
                continue
            available.add(track.name)
            for strip in strips:
                available.add(strip.action.name)
                if track.name == track_name:
                    named_tracks.append((data, strip.action, getattr(strip, "action_slot", None)))
                elif strip.action.name == clip:
                    named_actions.append((data, strip.action, getattr(strip, "action_slot", None)))
        if not data.nla_tracks and data.action is not None:
            available.add(data.action.name)
            if data.action.name == clip:
                named_actions.append((data, data.action, getattr(data, "action_slot", None)))
        data.action = None

    if clip is None:
        return
    matches = named_tracks or named_actions
    if not matches:
        names = ", ".join(repr(name) for name in sorted(available)) or "none"
        raise JobError(f"{item['id']!r}: animation {clip!r} not found. Available clips/actions: {names}")
    if len({data.as_pointer() for data, _, _ in matches}) != len(matches):
        raise JobError(f"{item['id']!r}: animation {clip!r} has multiple actions for one target")

    clip_end = max(float(action.frame_range[1]) for _, action, _ in matches)
    # An action containing only a pose at time zero is constant.
    clip_end = clip_end if clip_end > 0.0 else 1.0
    for data, action, slot in matches:
        data.use_nla = True
        track = data.nla_tracks.new()
        track.name = f"Playback: {clip}"
        strip = track.strips.new(action.name, 1, action)
        if slot is not None:
            strip.action_slot = slot
        set_strip_timing(strip, clip_end, frame_count, item["loopAnimation"])
    LOG.info("Object %r uses %r on %d target(s), loop=%s",
             item["id"], clip, len(matches), item["loopAnimation"])


def import_glb(path):
    # Use the glTF add-on's import hook to leave the asset in its authored pose.
    # Otherwise Blender can evaluate the first clip during import and retain
    # those values even after its active action is cleared.
    hook_called = False
    track_names = {}

    class ImportExtension:
        def gather_import_animations(self, animations, options, _gltf):
            nonlocal hook_called
            options.restore_first_anim = False
            for animation in animations or ():
                if animation.name:
                    track_names.setdefault(animation.name, animation.track_name)
            hook_called = True

    module_name = "_lightek_gltf_import"
    module = ModuleType(module_name)
    module.glTF2ImportUserExtension = ImportExtension
    addons = bpy.context.preferences.addons
    addon = addons.new()
    addon.module = module_name
    sys.modules[module_name] = module
    try:
        result = bpy.ops.import_scene.gltf(filepath=str(path))
    finally:
        addons.remove(addon)
        del sys.modules[module_name]

    if "FINISHED" in result and not hook_called:
        raise JobError("This Blender glTF importer does not expose the animation import hook")
    return result, track_names


def import_asset(scene, item, frame_count):
    path = item["glbPath"]
    LOG.info("Importing %r from %s", item["id"], path)
    before = set(bpy.data.objects)
    try:
        result, track_names = import_glb(path)
    except RuntimeError as error:
        raise JobError(f"Cannot import {item['id']!r} from {path}: {error}") from error
    imported = set(bpy.data.objects) - before
    if "FINISHED" not in result or not imported:
        raise JobError(f"GLB import created no objects for {item['id']!r}: {path}")

    root = bpy.data.objects.new(f"Asset | {item['id']}", None)
    scene.collection.objects.link(root)
    root["manifest_id"] = item["id"]
    # Reparent only asset roots. Their local transforms and animation curves
    # stay intact, including armature/skinned mesh and multi-root assets.
    for obj in imported:
        if obj.parent not in imported:
            obj.parent = root
        if obj.type == "LIGHT":
            obj.hide_render = True
    root.location = item["position"]
    root.rotation_mode = "XYZ"
    root.rotation_euler = tuple(math.radians(value) for value in item["rotationEulerDeg"])
    root.scale = item["scale"]
    activate_animation(animation_owners(imported), item, frame_count, track_names)


def build_camera(scene, spec):
    target = bpy.data.objects.new("Camera Target", None)
    scene.collection.objects.link(target)
    target.location = spec["target"]

    optics = bpy.data.cameras.new("Studio Camera")
    optics.sensor_fit = "HORIZONTAL"
    optics.sensor_width = 48.0
    optics.lens = optics.sensor_width / (2.0 * math.tan(math.radians(spec["fov"]) / 2.0))
    optics.clip_start = 0.01
    optics.clip_end = 10_000
    camera = bpy.data.objects.new("Studio Camera", optics)
    scene.collection.objects.link(camera)
    camera.location = spec["position"]
    tracking = camera.constraints.new("TRACK_TO")
    tracking.target = target
    tracking.track_axis = "TRACK_NEGATIVE_Z"
    tracking.up_axis = "UP_Y"
    scene.camera = camera


def add_light(scene, name, kind, focus, offset, energy, color, size):
    data = bpy.data.lights.new(name, kind)
    data.energy = energy
    data.color = color
    if kind == "AREA":
        data.shape = "DISK"
        data.size = size
    else:
        data.angle = math.radians(size)
    light = bpy.data.objects.new(name, data)
    scene.collection.objects.link(light)
    light.location = focus + Vector(offset)
    light.rotation_euler = (-Vector(offset)).to_track_quat("-Z", "Y").to_euler()


def build_lighting(scene, preset, target):
    world = bpy.data.worlds.new("Studio World")
    world.use_nodes = True
    scene.world = world
    background = world.node_tree.nodes.get("Background")
    focus = Vector(target)
    if preset == "studio_soft":
        background.inputs["Color"].default_value = (0.16, 0.19, 0.24, 1)
        background.inputs["Strength"].default_value = 0.4
        add_light(scene, "Soft Key", "AREA", focus, (-3, -4, 5), 850, (1, 0.89, 0.78), 5)
        add_light(scene, "Soft Fill", "AREA", focus, (4, -1, 2), 420, (0.68, 0.81, 1), 4)
        add_light(scene, "Soft Rim", "AREA", focus, (0, 4, 4), 700, (0.86, 0.93, 1), 3)
    elif preset == "dramatic_rim":
        background.inputs["Color"].default_value = (0.045, 0.055, 0.09, 1)
        background.inputs["Strength"].default_value = 0.25
        add_light(scene, "Dramatic Key", "AREA", focus, (-3, -2, 4), 620, (1, 0.72, 0.48), 2)
        add_light(scene, "Dramatic Rim", "AREA", focus, (1, 3, 2.5), 1250, (0.37, 0.63, 1), 1.25)
        add_light(scene, "Dramatic Fill", "AREA", focus, (2, -3, 1.5), 90, (0.69, 0.76, 1), 3)
    else:
        background.inputs["Color"].default_value = (0.42, 0.62, 0.92, 1)
        background.inputs["Strength"].default_value = 0.5
        add_light(scene, "Sun", "SUN", focus, (-4, -3, 7), 2.8, (1, 0.93, 0.81), 1.5)
        add_light(scene, "Sky Fill", "AREA", focus, (2, 1, 7), 450, (0.63, 0.78, 1), 8)


def configure_scene(scene, manifest, frame_count):
    render = scene.render
    engine = ENGINES[manifest["renderEngine"]]
    try:
        render.engine = engine
    except TypeError:
        # Blender 5 renamed EEVEE's engine identifier after its Next rewrite.
        if engine != "BLENDER_EEVEE_NEXT":
            raise
        render.engine = "BLENDER_EEVEE"
    scene.view_settings.view_transform = "AgX"
    scene.render.film_transparent = False
    render.resolution_x, render.resolution_y = manifest["resolution"]
    render.resolution_percentage = 100
    render.pixel_aspect_x = render.pixel_aspect_y = 1
    render.fps = manifest["fps"]
    render.fps_base = 1
    scene.frame_start = 1
    scene.frame_end = frame_count
    scene.frame_step = 1
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1

    image = render.image_settings
    if hasattr(image, "media_type"):
        image.media_type = "VIDEO"
    else:
        image.file_format = "FFMPEG"
    image.color_mode = "RGB"
    render.use_file_extension = True
    render.ffmpeg.format = "MPEG4"
    render.ffmpeg.codec = "H264"
    render.ffmpeg.constant_rate_factor = "HIGH"
    render.ffmpeg.audio_codec = "NONE"
    if engine == "CYCLES":
        import _cycles

        scene.cycles.device = "CPU"
        scene.cycles.samples = 48
        scene.cycles.use_adaptive_sampling = True
        scene.cycles.adaptive_threshold = 0.035
        scene.cycles.use_denoising = bool(getattr(_cycles, "with_openimagedenoise", False))
        if scene.cycles.use_denoising:
            scene.cycles.denoiser = "OPENIMAGEDENOISE"


def enable_cycles_gpu(scene):
    addon = bpy.context.preferences.addons.get("cycles")
    if addon is not None:
        prefs = addon.preferences
        for backend in ("OPTIX", "CUDA", "HIP", "METAL", "ONEAPI"):
            try:
                prefs.compute_device_type = backend
                prefs.refresh_devices()
                devices = [device for device in prefs.devices if device.type == backend]
                if not devices:
                    continue
                chosen = devices[0]
                for device in prefs.devices:
                    device.use = device.id == chosen.id
                scene.cycles.device = "GPU"
                LOG.info("Cycles device: %s (%s)", chosen.name, backend)
                return True
            except (TypeError, ValueError, RuntimeError) as error:
                LOG.debug("Cycles backend %s unavailable: %s", backend, error)
    LOG.info("Cycles device: CPU (no compatible GPU detected)")
    return False


def render_movie(scene, output):
    with tempfile.TemporaryDirectory(prefix=".lightek-render-", dir=output.parent) as temp:
        scene.render.filepath = str(Path(temp) / "movie")
        result = bpy.ops.render.render(animation=True, scene=scene.name)
        candidates = list(Path(temp).glob("*.mp4"))
        if "FINISHED" not in result or len(candidates) != 1 or not candidates[0].stat().st_size:
            raise JobError("Blender did not produce a complete MP4")
        # Move the finished file out of the temporary directory atomically.
        os.replace(candidates[0], output)
